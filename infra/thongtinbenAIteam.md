I engine image is ready for EKS deployment.

  Image URI:
  589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0

  Pinned digest:
  589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine@sha256:ed9d9ca831aa70865e175a611359610c66be5cb56fd33b0487ac687fc4b14f70

  CDO account 629149146950 has been granted cross-account pull permission on the AIO ECR repo.

  Pull test:
  aws ecr get-login-password --region us-east-1 \
    | docker login --username AWS --password-stdin 589077667575.dkr.ecr.us-east-1.amazonaws.com

  docker pull 589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0

  EKS image field:
  image: 589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0

  Container:
  containerPort: 8080
  GET /healthz
  GET /readyz
  GET /metrics
  POST /v1/triage

  Release source:
  https://github.com/c0mmie-b0msh3ll/xBrain-capstone2/tree/v1.0.0

  Handoff doc:
  https://github.com/c0mmie-b0msh3ll/xBrain-capstone2/blob/v1.0.0/capstone/tf-1/ai/docs/11_v1_0_0_handoff.md

  Smoke test sample:
  https://github.com/c0mmie-b0msh3ll/xBrain-capstone2/blob/v1.0.0/capstone/tf-1/ai/engine-skeleton/samples/latency-degradation.request.json