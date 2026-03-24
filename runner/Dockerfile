# =============================================================================
# Stage 1: Build the Rust gRPC server
# =============================================================================
FROM rust:1.94-bookworm AS builder

RUN apt-get update && apt-get install -y protobuf-compiler libprotobuf-dev --no-install-recommends && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Cache dependency compilation: copy manifests first, build a dummy, then copy real source.
COPY Cargo.toml Cargo.lock* ./
COPY build.rs ./
COPY proto/ proto/
RUN mkdir src && echo 'fn main() { println!("dummy"); }' > src/main.rs
RUN cargo build --release 2>/dev/null || true
RUN rm -rf src

# Build the real binary
COPY src/ src/
RUN touch src/main.rs && cargo build --release

# =============================================================================
# Stage 2: Fetch Terraform binary
# =============================================================================
FROM debian:bookworm-slim AS terraform

ARG TERRAFORM_VERSION=1.9.8
ARG TARGETARCH

RUN apt-get update && apt-get install -y curl unzip ca-certificates --no-install-recommends && rm -rf /var/lib/apt/lists/*

RUN ARCH=$(case "${TARGETARCH}" in \
  amd64) echo "amd64" ;; \
  arm64) echo "arm64" ;; \
  *) echo "amd64" ;; \
  esac) && \
  curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" \
  -o /tmp/terraform.zip && \
  unzip /tmp/terraform.zip -d /usr/local/bin/ && \
  rm /tmp/terraform.zip && \
  terraform version

# =============================================================================
# Stage 3: Final minimal runtime image
# =============================================================================
FROM debian:bookworm-slim

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
  && rm -rf /var/lib/apt/lists/*

# Non-root user for security
RUN groupadd -r runner && useradd -r -g runner -d /home/runner -m runner

# Terraform CLI
COPY --from=terraform /usr/local/bin/terraform /usr/local/bin/terraform

# tf-runner gRPC server
COPY --from=builder /build/target/release/tf-runner /usr/local/bin/tf-runner

# Terraform plugin cache directory (reduces re-downloads across runs)
ENV TF_PLUGIN_CACHE_DIR=/home/runner/.terraform.d/plugin-cache
RUN mkdir -p "${TF_PLUGIN_CACHE_DIR}" && chown -R runner:runner /home/runner

USER runner
WORKDIR /home/runner

# gRPC port
EXPOSE 50051

ENV PORT=50051
ENV RUST_LOG=info

ENTRYPOINT ["tf-runner"]
