# FinCorp Pipeline Guide

## CodeArtifact as Secure Upstream Proxy

CodeArtifact acts as a caching proxy between CodeBuild and the public npm/PyPI registries. Packages are:
1. Fetched once from npmjs.org through the `public:npmjs` external connection
2. Cached in the `npm-store` repository
3. Future installs served from CodeArtifact - no direct internet dependency

This prevents supply chain attacks via dependency confusion and ensures reproducible builds.

## Tag Immutability

ECR is configured with `image_tag_mutability = "IMMUTABLE"`. This means:
- Once `fincorp-app:abc123` is pushed, it cannot be overwritten
- Rollbacks are reliable - the tag always points to the same image layer digest
- Audit trail is preserved in ECR image history

## Scan-on-Push and Vulnerability Gate

Every pushed image is automatically scanned by Amazon Inspector (Basic scanning).

The `buildspec.yml` post-build phase:
1. Waits 60 seconds for scan results
2. Queries HIGH and CRITICAL finding counts
3. **Exits with code 1 if any HIGH or CRITICAL vulnerabilities are found**
4. This causes CodePipeline to mark the stage as failed and halt deployment

To view scan results: AWS Console -> ECR -> Repositories -> fincorp-app -> Images -> [tag] -> Vulnerabilities

## Triggering a Deliberate Build Failure

To demonstrate the vulnerability gate in a lab, use a Dockerfile with known-vulnerable packages:

```dockerfile
FROM node:14-alpine
# node:14 is EOL and contains known HIGH/CRITICAL CVEs
RUN npm install lodash@4.17.4
```

Push this change and watch CodePipeline fail at the Build_and_Scan stage.
