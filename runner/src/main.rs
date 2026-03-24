use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::{transport::Server, Request, Response, Status};
use tracing::{error, info, warn};

pub mod pb {
    tonic::include_proto!("terraform.runner.v1");
}

use pb::log_line::Stream as LogStream;
use pb::terraform_runner_server::{TerraformRunner, TerraformRunnerServer};
use pb::*;

// ---------------------------------------------------------------------------
// gRPC service
// ---------------------------------------------------------------------------

#[derive(Debug, Default)]
pub struct TfRunnerService;

#[tonic::async_trait]
impl TerraformRunner for TfRunnerService {
    type PlanStream = ReceiverStream<Result<PlanEvent, Status>>;

    async fn plan(
        &self,
        request: Request<PlanRequest>,
    ) -> Result<Response<Self::PlanStream>, Status> {
        let req = request.into_inner();
        let op_id = req.operation_id.clone();
        info!(operation_id = %op_id, "plan requested");

        let (tx, rx) = mpsc::channel(256);

        tokio::spawn(async move {
            let result = execute_plan(req, tx.clone()).await;
            if let Err(e) = result {
                error!(operation_id = %op_id, error = %e, "plan failed");
                let _ = tx
                    .send(Ok(PlanEvent {
                        event: Some(plan_event::Event::Result(PlanResult {
                            success: false,
                            error_message: e.to_string(),
                            ..Default::default()
                        })),
                    }))
                    .await;
            }
        });

        Ok(Response::new(ReceiverStream::new(rx)))
    }
}

// ---------------------------------------------------------------------------
// Plan execution
// ---------------------------------------------------------------------------

async fn execute_plan(req: PlanRequest, tx: mpsc::Sender<Result<PlanEvent, Status>>) -> Result<()> {
    let source = req.source.as_ref().context("missing blueprint source")?;
    let backend = req.backend.as_ref().context("missing backend config")?;

    // 1. Clone blueprint from git
    info!(
        repo = %source.repo_url,
        git_ref = %source.git_ref,
        path = %source.path,
        "fetching blueprint from git"
    );
    stream_log(
        &tx,
        LogStream::Stdout,
        format!(
            "Cloning blueprint from {} @ {}",
            source.repo_url, source.git_ref
        ),
    )
    .await;

    let work_dir = clone_blueprint(source).await?;

    // 2. Inject backend.tf and tfvars
    inject_backend_and_vars(&work_dir, backend, &req.variables)?;

    let env = build_env(&req.env_vars);

    // 3. terraform init
    let (code, stderr) = run_terraform(&["init", "-no-color"], &work_dir, &env, &tx).await?;

    if code != 0 {
        send_result(&tx, false, format!("terraform init failed: {stderr}")).await;
        cleanup(&work_dir);
        return Ok(());
    }

    // 4. terraform plan -out=plan.bin
    let (code, stderr) = run_terraform(
        &["plan", "-out=plan.bin", "-no-color", "-detailed-exitcode"],
        &work_dir,
        &env,
        &tx,
    )
    .await?;

    // Exit code 2 = success with changes, 0 = no changes, anything else = error.
    if code != 0 && code != 2 {
        send_result(&tx, false, format!("terraform plan failed: {stderr}")).await;
        cleanup(&work_dir);
        return Ok(());
    }

    // 5. terraform show -json plan.bin  (raw diff for q-core)
    let show_output = Command::new("terraform")
        .args(["show", "-json", "plan.bin"])
        .current_dir(&work_dir)
        .env_clear()
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .output()
        .await
        .context("failed to run terraform show")?;

    let plan_json = show_output.stdout;

    // 6. Read the binary planfile (q-core stores this, engine uses it for apply)
    let plan_binary =
        std::fs::read(work_dir.join("plan.bin")).context("failed to read plan.bin")?;

    // 7. Parse summary counts from the plan JSON
    let (add, change, destroy) = parse_plan_counts(&plan_json);

    tx.send(Ok(PlanEvent {
        event: Some(plan_event::Event::Result(PlanResult {
            success: true,
            error_message: String::new(),
            plan_json,
            plan_binary,
            resources_to_add: add,
            resources_to_change: change,
            resources_to_destroy: destroy,
        })),
    }))
    .await
    .ok();

    cleanup(&work_dir);
    Ok(())
}

async fn send_result(tx: &mpsc::Sender<Result<PlanEvent, Status>>, success: bool, error: String) {
    let _ = tx
        .send(Ok(PlanEvent {
            event: Some(plan_event::Event::Result(PlanResult {
                success,
                error_message: error,
                ..Default::default()
            })),
        }))
        .await;
}

/// Send a single log line to the gRPC stream.
async fn stream_log(tx: &mpsc::Sender<Result<PlanEvent, Status>>, stream: LogStream, line: String) {
    let _ = tx
        .send(Ok(PlanEvent {
            event: Some(plan_event::Event::Log(LogLine {
                stream: stream.into(),
                line,
            })),
        }))
        .await;
}

// ---------------------------------------------------------------------------
// Blueprint fetching (git clone)
// ---------------------------------------------------------------------------

/// Shallow-clone a public git repo at a specific ref, return the blueprint directory.
async fn clone_blueprint(source: &BlueprintSource) -> Result<PathBuf> {
    let clone_dir = tempfile::TempDir::new()
        .context("failed to create clone temp dir")?
        .keep();

    let output = Command::new("git")
        .args([
            "clone",
            "--depth=1",
            "--single-branch",
            "--branch",
            &source.git_ref,
            &source.repo_url,
            clone_dir.to_str().unwrap(),
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .context("failed to spawn git clone")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!(
            "git clone failed (exit {}): repo={} ref={}\n{}",
            output.status.code().unwrap_or(-1),
            source.repo_url,
            source.git_ref,
            stderr.trim()
        );
    }

    // Resolve the blueprint subdirectory
    if source.path.is_empty() {
        Ok(clone_dir)
    } else {
        let sub = clone_dir.join(&source.path);
        if !sub.is_dir() {
            bail!(
                "blueprint path '{}' not found in repo at ref '{}'",
                source.path,
                source.git_ref
            );
        }
        Ok(sub)
    }
}

// ---------------------------------------------------------------------------
// Workspace preparation
// ---------------------------------------------------------------------------

/// Inject backend.tf and terraform.tfvars.json into the blueprint directory.
fn inject_backend_and_vars(
    work_dir: &Path,
    backend: &S3BackendConfig,
    variables: &std::collections::HashMap<String, String>,
) -> Result<()> {
    let backend_tf = generate_backend_tf(backend);
    std::fs::write(work_dir.join("backend.tf"), backend_tf)
        .context("failed to write backend.tf")?;

    if !variables.is_empty() {
        let tfvars_json =
            serde_json::to_string_pretty(variables).context("failed to serialize variables")?;
        std::fs::write(work_dir.join("terraform.tfvars.json"), tfvars_json)
            .context("failed to write terraform.tfvars.json")?;
    }

    Ok(())
}

/// Generate backend.tf for S3 state storage.
fn generate_backend_tf(cfg: &S3BackendConfig) -> String {
    let mut hcl = format!(
        r#"terraform {{
  backend "s3" {{
    bucket  = "{bucket}"
    key     = "{key}"
    region  = "{region}"
    encrypt = {encrypt}
"#,
        bucket = cfg.bucket,
        key = cfg.key,
        region = cfg.region,
        encrypt = cfg.encrypt,
    );

    if !cfg.dynamodb_table.is_empty() {
        hcl.push_str(&format!(
            "    dynamodb_table = \"{}\"\n",
            cfg.dynamodb_table
        ));
    }

    hcl.push_str("  }\n}\n");
    hcl
}

// ---------------------------------------------------------------------------
// Terraform subprocess
// ---------------------------------------------------------------------------

/// Build the sanitised environment for the Terraform child process.
fn build_env(env_vars: &[EnvVar]) -> Vec<(String, String)> {
    let mut env: Vec<(String, String)> = Vec::new();

    // Inherit essentials from the container environment
    let inherit = [
        "PATH",
        "HOME",
        "TF_PLUGIN_CACHE_DIR",
        // AWS credentials for the S3 state backend (set on the Qovery service)
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
    ];
    for key in inherit {
        if let Ok(val) = std::env::var(key) {
            env.push((key.into(), val));
        }
    }

    // Automation flags
    env.push(("TF_INPUT".into(), "false".into()));
    env.push(("TF_IN_AUTOMATION".into(), "1".into()));

    // Caller-provided env vars (e.g. customer credentials for the TF provider).
    // These are added last so they can override inherited values if needed.
    for var in env_vars {
        env.push((var.name.clone(), var.value.clone()));
    }

    env
}

/// Spawn `terraform <args>`, streaming stdout/stderr as PlanEvent log lines.
/// Returns (exit_code, collected_stderr).
async fn run_terraform(
    args: &[&str],
    work_dir: &Path,
    env: &[(String, String)],
    tx: &mpsc::Sender<Result<PlanEvent, Status>>,
) -> Result<(i32, String)> {
    let mut cmd = Command::new("terraform");
    cmd.args(args)
        .current_dir(work_dir)
        .env_clear()
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    info!(args = ?args, "running terraform");

    let mut child = cmd.spawn().context("failed to spawn terraform")?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let tx_out = tx.clone();
    let stdout_handle = tokio::spawn(async move {
        let reader = BufReader::new(stdout);
        let mut lines = reader.lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let _ = tx_out
                .send(Ok(PlanEvent {
                    event: Some(plan_event::Event::Log(LogLine {
                        stream: LogStream::Stdout.into(),
                        line,
                    })),
                }))
                .await;
        }
    });

    let tx_err = tx.clone();
    let stderr_handle = tokio::spawn(async move {
        let reader = BufReader::new(stderr);
        let mut lines = reader.lines();
        let mut collected = Vec::new();
        while let Ok(Some(line)) = lines.next_line().await {
            collected.push(line.clone());
            let _ = tx_err
                .send(Ok(PlanEvent {
                    event: Some(plan_event::Event::Log(LogLine {
                        stream: LogStream::Stderr.into(),
                        line,
                    })),
                }))
                .await;
        }
        collected.join("\n")
    });

    let status = child.wait().await.context("failed to wait for terraform")?;
    let _ = stdout_handle.await;
    let stderr_text = stderr_handle.await.unwrap_or_default();

    let code = status.code().unwrap_or(-1);
    info!(exit_code = code, "terraform exited");

    Ok((code, stderr_text))
}

// ---------------------------------------------------------------------------
// Plan JSON parsing
// ---------------------------------------------------------------------------

/// Extract resource change counts from `terraform show -json` output.
fn parse_plan_counts(plan_json: &[u8]) -> (i32, i32, i32) {
    let parsed: serde_json::Value = match serde_json::from_slice(plan_json) {
        Ok(v) => v,
        Err(_) => return (0, 0, 0),
    };

    let mut add = 0i32;
    let mut change = 0i32;
    let mut destroy = 0i32;

    if let Some(changes) = parsed.get("resource_changes").and_then(|v| v.as_array()) {
        for rc in changes {
            let actions: Vec<&str> = rc
                .get("change")
                .and_then(|c| c.get("actions"))
                .and_then(|a| a.as_array())
                .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect())
                .unwrap_or_default();

            match actions.as_slice() {
                ["create"] => add += 1,
                ["update"] => change += 1,
                ["delete"] => destroy += 1,
                ["delete", "create"] | ["create", "delete"] => {
                    destroy += 1;
                    add += 1;
                }
                _ => {}
            }
        }
    }

    (add, change, destroy)
}

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

fn cleanup(work_dir: &Path) {
    if let Err(e) = std::fs::remove_dir_all(work_dir) {
        warn!(path = %work_dir.display(), error = %e, "failed to cleanup work dir");
    }
}

// ---------------------------------------------------------------------------
// Entrypoint
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .json()
        .init();

    let port = std::env::var("PORT").unwrap_or_else(|_| "50051".into());
    let addr = format!("0.0.0.0:{port}").parse()?;

    info!(%addr, "starting tf-runner (plan-only) gRPC server");

    Server::builder()
        .add_service(TerraformRunnerServer::new(TfRunnerService))
        .serve(addr)
        .await
        .context("gRPC server failed")?;

    Ok(())
}
