use anyhow::{Context, Result};
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

async fn execute_plan(
    req: PlanRequest,
    tx: mpsc::Sender<Result<PlanEvent, Status>>,
) -> Result<()> {
    let backend = req.backend.as_ref().context("missing backend config")?;
    let work_dir = prepare_workspace(&req.files, backend, &req.variables)?;
    let env = build_env(&req.env_vars);

    // 1. terraform init
    let (code, stderr) = run_terraform(
        &["init", "-no-color"],
        &work_dir,
        &env,
        &tx,
    )
    .await?;

    if code != 0 {
        send_result(&tx, false, format!("terraform init failed: {stderr}")).await;
        cleanup(&work_dir);
        return Ok(());
    }

    // 2. terraform plan -out=plan.bin
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

    // 3. terraform show -json plan.bin  (raw diff for q-core)
    let show_output = Command::new("terraform")
        .args(["show", "-json", "plan.bin"])
        .current_dir(&work_dir)
        .env_clear()
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .output()
        .await
        .context("failed to run terraform show")?;

    let plan_json = show_output.stdout;

    // 4. Read the binary planfile (q-core stores this, engine uses it for apply)
    let plan_binary =
        std::fs::read(work_dir.join("plan.bin")).context("failed to read plan.bin")?;

    // 5. Parse summary counts from the plan JSON
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

async fn send_result(
    tx: &mpsc::Sender<Result<PlanEvent, Status>>,
    success: bool,
    error: String,
) {
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

// ---------------------------------------------------------------------------
// Workspace preparation
// ---------------------------------------------------------------------------

/// Write blueprint files, generated backend.tf, and tfvars into a temp directory.
fn prepare_workspace(
    files: &[BlueprintFile],
    backend: &S3BackendConfig,
    variables: &std::collections::HashMap<String, String>,
) -> Result<PathBuf> {
    let work_dir = tempfile::TempDir::new()
        .context("failed to create temp dir")?
        .keep();

    // Write blueprint files sent by q-core
    for file in files {
        let dest = work_dir.join(&file.path);
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("failed to create dir for {}", file.path))?;
        }
        std::fs::write(&dest, &file.content)
            .with_context(|| format!("failed to write {}", file.path))?;
    }

    // Inject backend.tf for S3 state
    let backend_tf = generate_backend_tf(backend);
    std::fs::write(work_dir.join("backend.tf"), backend_tf)
        .context("failed to write backend.tf")?;

    // Write variables to terraform.tfvars.json
    if !variables.is_empty() {
        let tfvars_json =
            serde_json::to_string_pretty(variables).context("failed to serialize variables")?;
        std::fs::write(work_dir.join("terraform.tfvars.json"), tfvars_json)
            .context("failed to write terraform.tfvars.json")?;
    }

    Ok(work_dir)
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

    // Inherit essentials
    if let Ok(path) = std::env::var("PATH") {
        env.push(("PATH".into(), path));
    }
    if let Ok(home) = std::env::var("HOME") {
        env.push(("HOME".into(), home));
    }
    // Inherit TF plugin cache dir if set
    if let Ok(cache) = std::env::var("TF_PLUGIN_CACHE_DIR") {
        env.push(("TF_PLUGIN_CACHE_DIR".into(), cache));
    }

    // Automation flags
    env.push(("TF_INPUT".into(), "false".into()));
    env.push(("TF_IN_AUTOMATION".into(), "1".into()));

    // Caller-provided credentials and config
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

    // Stream stdout
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

    // Stream stderr and collect it for error reporting
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
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
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
