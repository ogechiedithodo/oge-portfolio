# CI/CD Pipeline with Trivy, Docker Hub, GitHub Secrets and SSH Deployment

This project demonstrates a basic **DevSecOps CI/CD pipeline** using GitHub Actions.

The pipeline performs the following tasks:

```text
Developer pushes code
        ↓
GitHub Actions starts
        ↓
Install dependencies
        ↓
Run tests
        ↓
Run lint checks
        ↓
Build application
        ↓
Trivy scans project files
        ↓
Build Docker image
        ↓
Trivy scans Docker image
        ↓
Push image to Docker Hub
        ↓
SSH into deployment server
        ↓
Pull new image
        ↓
Stop old container
        ↓
Start new container
```

The objective of this README is not only to show the pipeline, but also to explain what each part does so that a student can understand how CI, security scanning, containerization, secrets, and deployment work together.

---

# 1. Technologies Used

This pipeline uses:

- **GitHub Actions** — automation platform used to run the CI/CD pipeline.
- **Node.js** — runtime used to install dependencies and build the application.
- **Trivy** — vulnerability scanner.
- **Docker** — packages the application into a container image.
- **Docker Hub** — stores the Docker image.
- **GitHub Secrets** — securely stores credentials used by the pipeline.
- **SSH** — allows GitHub Actions to connect to the deployment server.
- **Nginx** — can be used to serve the built frontend application inside the Docker container.

---

# 2. GitHub Secrets Required

Go to:

```text
Repository
→ Settings
→ Secrets and variables
→ Actions
→ New repository secret
```

Create the following secrets:

| Secret | Purpose |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `SSH_HOST` | IP address or hostname of the deployment server |
| `SSH_USERNAME` | Linux user used to connect to the server |
| `SSH_PASSWORD` | SSH password |
| `SSH_PORT` | SSH port, normally `22` |

Example:

```text
DOCKERHUB_USERNAME=ogeusername
DOCKERHUB_TOKEN=xxxxxxxxxxxxxxxx

SSH_HOST=192.0.2.10
SSH_USERNAME=ubuntu
SSH_PASSWORD=xxxxxxxxxxxxxxxx
SSH_PORT=22
```

Never put real passwords, API keys, or access tokens directly inside the workflow file.

GitHub Secrets lets the workflow reference them like this:

```yaml
${{ secrets.SSH_HOST }}
```

GitHub supplies the value when the workflow runs.

---

# 3. Pipeline File Location

Create the workflow here:

```text
.github/workflows/ci-cd.yml
```

GitHub automatically looks inside:

```text
.github/workflows/
```

for workflow files ending in `.yml` or `.yaml`.

---

# 4. Complete Pipeline

```yaml
name: CI Security Docker CD

on:
  push:
    branches:
      - main

  pull_request:
    branches:
      - main

permissions:
  contents: read

env:
  IMAGE_NAME: ${{ secrets.DOCKERHUB_USERNAME }}/oge-portfoliofor

jobs:

  ci:
    name: CI - Build Application
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test --if-present

      - name: Run lint
        run: npm run lint --if-present

      - name: Build application
        run: npm run build


  security-scan:
    name: Security - Trivy Scan
    runs-on: ubuntu-latest

    needs:
      - ci

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run Trivy filesystem scan
        uses: aquasecurity/trivy-action@v0.36.0
        with:
          scan-type: fs
          scan-ref: .
          severity: HIGH,CRITICAL
          ignore-unfixed: true
          exit-code: "1"


  docker:
    name: Docker - Build Scan and Push
    runs-on: ubuntu-latest

    needs:
      - security-scan

    if: github.event_name == 'push'

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Login to Docker Hub
        uses: docker/login-action@v4
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build Docker image
        uses: docker/build-push-action@v7
        with:
          context: .
          load: true
          push: false
          tags: |
            ${{ env.IMAGE_NAME }}:${{ github.sha }}
            ${{ env.IMAGE_NAME }}:latest

      - name: Scan Docker image with Trivy
        uses: aquasecurity/trivy-action@v0.36.0
        with:
          image-ref: ${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: table
          severity: HIGH,CRITICAL
          ignore-unfixed: true
          exit-code: "1"

      - name: Push Docker image
        uses: docker/build-push-action@v7
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:${{ github.sha }}
            ${{ env.IMAGE_NAME }}:latest


  deploy:
    name: CD - Deploy to Server
    runs-on: ubuntu-latest

    needs:
      - docker

    if: github.ref == 'refs/heads/main'

    steps:
      - name: Deploy using SSH
        uses: appleboy/ssh-action@v1.2.5

        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USERNAME }}
          password: ${{ secrets.SSH_PASSWORD }}
          port: ${{ secrets.SSH_PORT }}

          script: |

            echo "Logging into Docker Hub..."

            echo "${{ secrets.DOCKERHUB_TOKEN }}" | docker login \
              -u "${{ secrets.DOCKERHUB_USERNAME }}" \
              --password-stdin

            echo "Pulling new Docker image..."

            docker pull \
              ${{ secrets.DOCKERHUB_USERNAME }}/oge-portfoliofor:${{ github.sha }}

            echo "Stopping old container..."

            docker stop oge-portfoliofor || true

            echo "Removing old container..."

            docker rm oge-portfoliofor || true

            echo "Starting new container..."

            docker run -d \
              --name oge-portfoliofor \
              --restart unless-stopped \
              -p 80:80 \
              ${{ secrets.DOCKERHUB_USERNAME }}/oge-portfoliofor:${{ github.sha }}

            echo "Removing unused Docker images..."

            docker image prune -f

            echo "Deployment successful."
```

---

# 5. Understanding the Beginning of the Workflow

## `name`

```yaml
name: CI Security Docker CD
```

This gives the workflow a readable name.

Inside the **Actions** tab in GitHub, the workflow will appear as:

```text
CI Security Docker CD
```

The name does not affect how the pipeline works. It only makes it easier for humans to identify.

---

# 6. Workflow Triggers

```yaml
on:
```

The `on` keyword tells GitHub:

> When should this pipeline run?

Everything underneath `on` defines an event that can start the workflow.

---

## Push Trigger

```yaml
  push:
```

This means the workflow should start when code is pushed to GitHub.

However, we do not want every branch to trigger it.

So we add:

```yaml
    branches:
```

This tells GitHub that we want to specify particular branches.

Then:

```yaml
      - main
```

means:

> Run the workflow when code is pushed to the `main` branch.

Example:

```bash
git push origin main
```

This starts the workflow.

A push to:

```bash
git push origin feature/login
```

will not trigger this particular `push` rule.

---

## Pull Request Trigger

```yaml
  pull_request:
```

This tells GitHub to also run the workflow when a pull request targets a configured branch.

Then:

```yaml
    branches:
```

means we are specifying which destination branch matters.

```yaml
      - main
```

means:

> Run the workflow when someone creates or updates a pull request whose target is `main`.

For example:

```text
feature/navbar
     ↓
Pull Request
     ↓
main
```

The CI and security checks can therefore run before the code is merged.

This is important because developers can find problems before code reaches production.

---

# 7. Workflow Permissions

```yaml
permissions:
```

GitHub Actions can be given different permissions.

This section limits what the workflow can do.

```yaml
  contents: read
```

means:

> The workflow may read repository contents, but it is not automatically given permission to modify them.

This follows the security principle called:

```text
Least Privilege
```

Least privilege means giving a system only the permissions it actually needs.

---

# 8. Environment Variables

```yaml
env:
```

The `env` section defines environment variables that can be reused by the workflow.

```yaml
  IMAGE_NAME: ${{ secrets.DOCKERHUB_USERNAME }}/oge-portfoliofor
```

This creates an environment variable called:

```text
IMAGE_NAME
```

Its value will look similar to:

```text
ogeusername/oge-portfoliofor
```

The Docker Hub username comes from:

```yaml
${{ secrets.DOCKERHUB_USERNAME }}
```

Because `IMAGE_NAME` is defined globally, different jobs can reuse it.

Instead of repeatedly writing:

```text
ogeusername/oge-portfoliofor
```

we can use:

```yaml
${{ env.IMAGE_NAME }}
```

---

# 9. Jobs

```yaml
jobs:
```

Every major unit of work inside GitHub Actions is called a **job**.

Our pipeline has four jobs:

```text
ci
security-scan
docker
deploy
```

They form this sequence:

```text
ci
 ↓
security-scan
 ↓
docker
 ↓
deploy
```

---

# 10. CI Job

```yaml
  ci:
```

`ci` is the internal ID of the first job.

CI means:

```text
Continuous Integration
```

The purpose of CI is to automatically check that new code still installs, tests, lints, and builds correctly.

---

```yaml
    name: CI - Build Application
```

This is the human-readable name displayed in GitHub Actions.

---

```yaml
    runs-on: ubuntu-latest
```

GitHub Actions needs a machine on which to execute commands.

This tells GitHub:

> Create a temporary Ubuntu runner and execute this job there.

The runner is created for the job and discarded after the job finishes.

It is not your production server.

---

# 11. Steps

```yaml
    steps:
```

A job is made up of individual steps.

Each step normally performs one task.

For example:

```text
Checkout code
Install Node.js
Install dependencies
Test
Lint
Build
```

---

# 12. Checkout Repository

```yaml
      - name: Checkout repository
```

`name` describes the step in a human-readable way.

GitHub Actions will display:

```text
Checkout repository
```

inside the workflow logs.

---

```yaml
        uses: actions/checkout@v4
```

`uses` means:

> Use an existing GitHub Action.

`actions/checkout` is GitHub's official action for downloading the repository code onto the runner.

Without this step, the runner would start without your application files.

`@v4` means version 4 of the checkout action is used.

After this step the runner has files such as:

```text
package.json
src/
public/
Dockerfile
```

available locally.

---

# 13. Setup Node.js

```yaml
      - name: Setup Node.js
```

This creates another pipeline step.

---

```yaml
        uses: actions/setup-node@v4
```

This uses GitHub's official Node.js setup action.

It installs and configures Node.js on the runner.

---

```yaml
        with:
```

`with` supplies configuration values to an action.

---

```yaml
          node-version: "22"
```

This tells the action to use Node.js version 22.

The quotes make the value explicitly a string.

---

```yaml
          cache: npm
```

This enables caching for npm dependencies.

Caching can make future pipeline runs faster because GitHub can reuse previously downloaded npm package data where appropriate.

---

# 14. Install Dependencies

```yaml
      - name: Install dependencies
```

This names the step.

---

```yaml
        run: npm ci
```

`run` means:

> Execute this shell command on the runner.

`npm ci` installs dependencies from the project's `package-lock.json`.

For CI pipelines, `npm ci` is normally preferred over:

```bash
npm install
```

because it performs a clean and reproducible installation based on the lock file.

If dependency installation fails, the job fails.

Because later jobs depend on this one, the pipeline also stops progressing.

---

# 15. Run Tests

```yaml
      - name: Run tests
```

This names the testing step.

---

```yaml
        run: npm test --if-present
```

This executes the application's test command.

The option:

```text
--if-present
```

means:

> Run the test script if the project has one.

If `package.json` contains:

```json
"scripts": {
  "test": "vitest"
}
```

the tests run.

If there is no test script, npm does not fail simply because the script is missing.

This is convenient for a basic classroom project.

For a stricter production pipeline, you may want tests to be mandatory.

---

# 16. Run Lint

```yaml
      - name: Run lint
```

This creates the linting step.

Linting checks code quality and style problems.

---

```yaml
        run: npm run lint --if-present
```

This runs the project's lint script if it exists.

For example:

```json
"scripts": {
  "lint": "eslint ."
}
```

A linting failure can stop bad or inconsistent code from moving further through the pipeline.

---

# 17. Build Application

```yaml
      - name: Build application
```

This names the build step.

---

```yaml
        run: npm run build
```

This runs the build command from `package.json`.

For a frontend application, this may produce a folder such as:

```text
dist/
```

or:

```text
build/
```

depending on the framework.

If the application cannot compile, this command fails.

That means we do not continue to security scanning, containerization, or deployment.

This is a major principle of CI/CD:

```text
Do not deploy code that cannot build.
```

---

# 18. Security Scan Job

```yaml
  security-scan:
```

This defines the second job.

Its internal ID is:

```text
security-scan
```

---

```yaml
    name: Security - Trivy Scan
```

This is the name shown in GitHub Actions.

---

```yaml
    runs-on: ubuntu-latest
```

This job gets its own fresh temporary Ubuntu runner.

Jobs do not automatically share the same runner.

---

# 19. Job Dependency with `needs`

```yaml
    needs:
```

`needs` tells GitHub that this job depends on another job.

---

```yaml
      - ci
```

This means:

> Do not start the security scan until the `ci` job has completed successfully.

The workflow becomes:

```text
CI
 ↓
Security Scan
```

If CI fails:

```text
CI ❌
Security Scan ⏭
```

The security job is skipped because its dependency did not pass.

---

# 20. Checkout Again

```yaml
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
```

You may wonder why we checkout the repository again.

The reason is that each job receives a separate runner.

The repository downloaded during the CI job does not automatically exist in the security job.

Therefore the second job must checkout the code again.

---

# 21. Trivy Filesystem Scan

```yaml
      - name: Run Trivy filesystem scan
```

This names the Trivy scanning step.

---

```yaml
        uses: aquasecurity/trivy-action@v0.36.0
```

This uses the official Trivy GitHub Action.

Trivy is a security scanner capable of checking things such as:

- operating-system packages,
- application dependencies,
- container images,
- filesystems,
- configuration problems,
- Infrastructure as Code,
- exposed secrets.

---

```yaml
        with:
```

This begins the Trivy configuration.

---

```yaml
          scan-type: fs
```

`fs` means:

```text
filesystem
```

So Trivy scans the checked-out repository files.

---

```yaml
          scan-ref: .
```

The dot:

```text
.
```

means:

> Scan the current directory.

Because the repository is checked out into the working directory, this means scanning the project.

---

```yaml
          severity: HIGH,CRITICAL
```

This tells Trivy to focus on vulnerabilities categorized as:

```text
HIGH
CRITICAL
```

For training, this is useful because it demonstrates how a team can define a security threshold.

---

```yaml
          ignore-unfixed: true
```

Sometimes Trivy finds a vulnerability for which no vendor fix currently exists.

Setting:

```text
ignore-unfixed: true
```

means those unfixed vulnerabilities are ignored for this scan.

This can reduce noise in a basic classroom pipeline.

In a real organization, the policy may be different.

---

```yaml
          exit-code: "1"
```

This is one of the most important lines in the security stage.

It means:

> If Trivy finds a vulnerability matching our configured policy, return exit code 1.

In Linux and CI/CD:

```text
0 = success
non-zero = failure
```

So Trivy can act as a security gate.

Example:

```text
Trivy finds CRITICAL vulnerability
            ↓
returns exit code 1
            ↓
GitHub job fails
            ↓
Docker image is not pushed
            ↓
Application is not deployed
```

This is an example of:

```text
Shift-Left Security
```

Security checks happen before deployment instead of after deployment.

---

# 22. Docker Job

```yaml
  docker:
```

This defines the third job.

---

```yaml
    name: Docker - Build Scan and Push
```

This is the displayed name.

This job performs three main activities:

```text
Build image
   ↓
Scan image
   ↓
Push image
```

---

```yaml
    runs-on: ubuntu-latest
```

Again, GitHub creates a temporary Ubuntu runner.

---

# 23. Docker Job Dependency

```yaml
    needs:
      - security-scan
```

This means the Docker job starts only if the Trivy filesystem scan passes.

The pipeline is now:

```text
CI
 ↓
Trivy filesystem scan
 ↓
Docker job
```

---

# 24. Only Run Docker Push on Push Events

```yaml
    if: github.event_name == 'push'
```

This is a condition.

It says:

> Run this job only when the workflow was triggered by a push.

Why?

Pull requests should normally test code, but we do not necessarily want a pull request to publish a production Docker image.

So:

```text
Pull Request
    ↓
CI
    ↓
Security Scan
    ↓
Docker Push skipped
```

But:

```text
Push to main
    ↓
CI
    ↓
Security Scan
    ↓
Docker Build/Push
```

---

# 25. Checkout for Docker Job

```yaml
      - name: Checkout repository
        uses: actions/checkout@v4
```

The Docker job receives a new runner, so the repository must again be downloaded.

---

# 26. Docker Buildx

```yaml
      - name: Setup Docker Buildx
```

This names the step.

---

```yaml
        uses: docker/setup-buildx-action@v4
```

Docker Buildx is an extended Docker build system.

It supports modern build features and works well with GitHub Actions.

The later `docker/build-push-action` uses this build system.

---

# 27. Login to Docker Hub

```yaml
      - name: Login to Docker Hub
```

This step authenticates the GitHub runner with Docker Hub.

---

```yaml
        uses: docker/login-action@v4
```

This uses Docker's GitHub Action for registry authentication.

---

```yaml
        with:
```

Begins configuration.

---

```yaml
          username: ${{ secrets.DOCKERHUB_USERNAME }}
```

The Docker Hub username comes from GitHub Secrets.

The username is not hardcoded.

---

```yaml
          password: ${{ secrets.DOCKERHUB_TOKEN }}
```

The Docker Hub access token also comes from GitHub Secrets.

An access token is preferred over using the main Docker Hub account password.

After this step, the runner can push images to Docker Hub.

---

# 28. Build Docker Image

```yaml
      - name: Build Docker image
```

Names the build step.

---

```yaml
        uses: docker/build-push-action@v7
```

This action builds Docker images from the project's Dockerfile.

---

```yaml
        with:
```

Begins configuration.

---

```yaml
          context: .
```

Docker's build context is the current repository directory.

Docker can therefore access files in the project required by the Dockerfile.

---

```yaml
          load: true
```

This tells Buildx to load the resulting image into the local Docker engine on the GitHub runner.

This is important because the next step needs to scan the local image with Trivy.

---

```yaml
          push: false
```

This means:

> Build the image, but do not push it to Docker Hub yet.

Why not?

Because we want to scan the image first.

The secure flow is:

```text
Build
 ↓
Scan
 ↓
Push
```

rather than:

```text
Build
 ↓
Push vulnerable image
 ↓
Scan later
```

---

# 29. Docker Image Tags

```yaml
          tags: |
```

This means multiple tags will be provided.

The pipe symbol:

```text
|
```

allows YAML to contain a multi-line value.

---

```yaml
            ${{ env.IMAGE_NAME }}:${{ github.sha }}
```

This creates an image tag using the Git commit SHA.

Example:

```text
ogeusername/oge-portfoliofor:5f8f2d3...
```

`github.sha` is the unique commit identifier for the commit that triggered the workflow.

This provides traceability.

You can identify exactly which Git commit produced a particular Docker image.

---

```yaml
            ${{ env.IMAGE_NAME }}:latest
```

This creates another tag:

```text
ogeusername/oge-portfoliofor:latest
```

`latest` provides a convenient human-friendly tag.

The commit SHA tag is better for traceability and rollback.

---

# 30. Scan Docker Image with Trivy

```yaml
      - name: Scan Docker image with Trivy
```

This starts a second Trivy scan.

The earlier scan checked the project filesystem.

This one checks the actual Docker image.

---

```yaml
        uses: aquasecurity/trivy-action@v0.36.0
```

Again, the Trivy GitHub Action is used.

---

```yaml
        with:
```

Begins the image scan settings.

---

```yaml
          image-ref: ${{ env.IMAGE_NAME }}:${{ github.sha }}
```

This tells Trivy which Docker image to scan.

It selects the image tagged with the current Git commit SHA.

---

```yaml
          format: table
```

This asks Trivy to display scan results in a readable table format in the GitHub Actions logs.

---

```yaml
          severity: HIGH,CRITICAL
```

Only HIGH and CRITICAL vulnerability levels are considered for this security gate.

---

```yaml
          ignore-unfixed: true
```

Again, known vulnerabilities without available fixes are ignored in this training setup.

---

```yaml
          exit-code: "1"
```

If Trivy finds vulnerabilities matching the configured policy, the step fails.

Because the next step depends on this job continuing successfully:

```text
Unsafe image
   ↓
Trivy fails
   ↓
Push step never runs
```

This prevents a vulnerable image from being published.

---

# 31. Push Docker Image

```yaml
      - name: Push Docker image
```

This step publishes the image.

It is reached only after the security scan passes.

---

```yaml
        uses: docker/build-push-action@v7
```

The Docker build/push action is used again.

---

```yaml
        with:
```

Begins configuration.

---

```yaml
          context: .
```

The current repository is used as the Docker build context.

---

```yaml
          push: true
```

This time the image should be uploaded to Docker Hub.

---

```yaml
          tags: |
```

Defines the tags that should be pushed.

---

```yaml
            ${{ env.IMAGE_NAME }}:${{ github.sha }}
```

Pushes the immutable commit-specific image tag.

---

```yaml
            ${{ env.IMAGE_NAME }}:latest
```

Also pushes the convenient `latest` tag.

After this step Docker Hub contains the image.

---

# 32. Deployment Job

```yaml
  deploy:
```

This defines the final job.

This is the **Continuous Deployment** section.

---

```yaml
    name: CD - Deploy to Server
```

Human-readable job name.

CD means:

```text
Continuous Deployment
```

The goal is to take the tested and scanned application and automatically deploy it.

---

```yaml
    runs-on: ubuntu-latest
```

GitHub creates another temporary Ubuntu runner.

This runner does not host the application.

It connects to the actual deployment server through SSH.

---

# 33. Deployment Dependency

```yaml
    needs:
      - docker
```

This tells GitHub:

> Deployment must wait for the Docker job.

Therefore:

```text
Docker build fails
        ↓
Deployment skipped
```

and:

```text
Docker security scan fails
        ↓
Docker image not pushed
        ↓
Deployment skipped
```

This creates a controlled deployment chain.

---

# 34. Deploy Only from Main

```yaml
    if: github.ref == 'refs/heads/main'
```

This condition checks the Git reference.

The full Git reference for the `main` branch is:

```text
refs/heads/main
```

Therefore deployment is allowed only when the workflow is running against `main`.

This is another protection against accidentally deploying feature branches.

---

# 35. SSH Deployment Step

```yaml
    steps:
      - name: Deploy using SSH
```

This creates the deployment step.

---

```yaml
        uses: appleboy/ssh-action@v1.2.5
```

This GitHub Action allows the runner to connect to another Linux server over SSH and execute commands there.

---

# 36. SSH Configuration

```yaml
        with:
```

Begins SSH configuration.

---

```yaml
          host: ${{ secrets.SSH_HOST }}
```

The target server address is retrieved from GitHub Secrets.

Example value:

```text
203.0.113.15
```

---

```yaml
          username: ${{ secrets.SSH_USERNAME }}
```

This provides the Linux username.

Example:

```text
ubuntu
```

---

```yaml
          password: ${{ secrets.SSH_PASSWORD }}
```

The SSH password is securely retrieved from GitHub Secrets.

It is not committed to the repository.

For a beginner training lab, password authentication is simple to demonstrate.

For production systems, SSH key authentication is usually preferable.

---

```yaml
          port: ${{ secrets.SSH_PORT }}
```

This defines the SSH port.

Normally:

```text
22
```

but storing it as a secret/configuration value makes the workflow reusable.

---

# 37. Remote Script

```yaml
          script: |
```

This means:

> Everything indented below this line should be executed on the remote server.

The pipe symbol allows us to write several shell commands.

These commands do not run on GitHub's runner.

They run on the deployment server after SSH authentication succeeds.

---

# 38. Deployment Messages

```bash
echo "Logging into Docker Hub..."
```

`echo` simply prints a message into the deployment logs.

It helps us understand what the pipeline is currently doing.

---

# 39. Docker Hub Login on the Server

```bash
echo "${{ secrets.DOCKERHUB_TOKEN }}" | docker login \
```

The Docker Hub token is passed into the Docker login command.

The pipe:

```text
|
```

takes the output from the command on the left and sends it to the command on the right.

---

```bash
-u "${{ secrets.DOCKERHUB_USERNAME }}" \
```

`-u` specifies the Docker Hub username.

The backslash:

```text
\
```

means the command continues on the next line.

It is mainly used to make long shell commands easier to read.

---

```bash
--password-stdin
```

This tells Docker to read the password/token from standard input instead of putting it directly in a command-line argument.

That is safer than writing:

```bash
docker login -u username -p password
```

---

# 40. Pull the New Docker Image

```bash
echo "Pulling new Docker image..."
```

Prints an informational message.

---

```bash
docker pull \
```

Downloads a Docker image from Docker Hub onto the server.

---

```bash
${{ secrets.DOCKERHUB_USERNAME }}/oge-portfoliofor:${{ github.sha }}
```

This tells Docker exactly which image version to download.

The tag uses the Git commit SHA.

This is important because the server deploys the exact image produced from the commit that triggered the workflow.

---

# 41. Stop Old Container

```bash
echo "Stopping old container..."
```

Displays a message.

---

```bash
docker stop oge-portfoliofor || true
```

Attempts to stop the currently running container called:

```text
oge-portfoliofor
```

The special part is:

```text
|| true
```

In shell scripting:

```text
command1 || command2
```

means:

> If command1 fails, run command2.

So if the container does not exist:

```bash
docker stop oge-portfoliofor
```

would normally return an error.

But:

```bash
|| true
```

makes the overall line succeed.

This is useful during the first deployment because there may be no old container yet.

---

# 42. Remove Old Container

```bash
echo "Removing old container..."
```

Prints a message.

---

```bash
docker rm oge-portfoliofor || true
```

Deletes the stopped container.

Again:

```text
|| true
```

prevents the deployment from failing if the container is not present.

A Docker container name must be available before we create another container using the same name.

---

# 43. Start New Container

```bash
echo "Starting new container..."
```

Prints a deployment message.

---

```bash
docker run -d \
```

`docker run` creates and starts a container.

`-d` means:

```text
detached mode
```

The container runs in the background.

Without `-d`, the SSH session would remain attached to the container process.

---

```bash
--name oge-portfoliofor \
```

This gives the container a predictable name:

```text
oge-portfoliofor
```

That makes future commands easy:

```bash
docker stop oge-portfoliofor
docker logs oge-portfoliofor
docker restart oge-portfoliofor
```

---

```bash
--restart unless-stopped \
```

This defines Docker's restart policy.

It means:

> Automatically restart the container if it crashes or the Docker service/server restarts, unless an administrator explicitly stopped it.

This improves application availability.

---

```bash
-p 80:80 \
```

This publishes a network port.

The format is:

```text
HOST_PORT:CONTAINER_PORT
```

So:

```text
80:80
```

means:

```text
Server port 80
       ↓
Container port 80
```

Users can therefore access the website using:

```text
http://SERVER_IP
```

assuming firewall/security rules permit port 80.

---

```bash
${{ secrets.DOCKERHUB_USERNAME }}/oge-portfoliofor:${{ github.sha }}
```

This tells Docker which image to use for the new container.

Again, the commit SHA ensures the exact tested image is deployed.

---

# 44. Remove Unused Docker Images

```bash
echo "Removing unused Docker images..."
```

Prints a message.

---

```bash
docker image prune -f
```

This removes dangling Docker images that are no longer required.

Without cleanup, repeated deployments can gradually consume disk space.

`-f` means:

```text
force
```

so Docker does not ask for interactive confirmation.

This is necessary because CI/CD pipelines cannot wait for a human to type `yes`.

---

# 45. Deployment Completed

```bash
echo "Deployment successful."
```

This prints a final success message.

If the script reaches this line without previous commands failing, the deployment process has completed.

---

# 46. Understanding the Complete Dependency Chain

The `needs` statements create this dependency chain:

```text
ci
 ↓
security-scan
 ↓
docker
 ↓
deploy
```

This means a later stage cannot proceed unless the required earlier stage succeeds.

For example:

## Scenario 1 — Application does not build

```text
CI ❌
Security ⏭
Docker ⏭
Deploy ⏭
```

Nothing is deployed.

---

## Scenario 2 — Trivy finds a critical vulnerability

```text
CI ✅
Security ❌
Docker ⏭
Deploy ⏭
```

The vulnerable application is blocked.

---

## Scenario 3 — Docker image has a critical vulnerability

```text
CI ✅
Filesystem Scan ✅
Docker Build ✅
Image Scan ❌
Docker Push ⏭
Deploy ⏭
```

The unsafe container image is not published or deployed.

---

## Scenario 4 — Everything passes

```text
CI ✅
Security ✅
Docker Build ✅
Docker Image Scan ✅
Docker Push ✅
Deployment ✅
```

The new application version becomes available on the server.

---

# 47. Why We Scan Twice

The pipeline performs two different Trivy scans.

## Filesystem Scan

```yaml
scan-type: fs
```

This scans the repository.

It can identify vulnerabilities connected with project files and dependencies.

Conceptually:

```text
Source Code
Dependencies
Configuration
       ↓
    Trivy
```

---

## Docker Image Scan

```yaml
image-ref: ${{ env.IMAGE_NAME }}:${{ github.sha }}
```

This scans the actual container image.

The container may contain vulnerabilities that are not obvious from the source repository alone.

For example, a vulnerable Linux package may exist in the base image.

Conceptually:

```text
Application
+
Node runtime
+
Linux base image
+
System packages
       ↓
Docker Image
       ↓
     Trivy
```

Therefore scanning both provides better coverage.

---

# 48. Why GitHub Secrets Matter

Never write credentials directly in a workflow:

```yaml
password: mypassword123
```

That would store the password in Git history.

Instead use:

```yaml
password: ${{ secrets.SSH_PASSWORD }}
```

The secret is configured separately in GitHub.

This separates:

```text
Code
```

from:

```text
Credentials
```

This is one of the basic principles of secure DevOps.

---

# 49. GitHub Secrets vs Secret Manager

For this training project, GitHub Secrets is being used to protect pipeline credentials.

Examples:

```text
Docker Hub token
SSH password
Server host
```

GitHub Secrets is very useful for CI/CD.

However, it is important to understand that GitHub Secrets is not the same as a full enterprise secrets-management platform.

More advanced tools include:

```text
HashiCorp Vault
AWS Secrets Manager
Azure Key Vault
Google Secret Manager
```

Those platforms can provide features such as:

- dynamic secrets,
- secret rotation,
- centralized access policies,
- detailed audit logs,
- short-lived credentials,
- application runtime secret delivery.

A useful learning progression is:

```text
GitHub Secrets
      ↓
Understand secret injection
      ↓
SSH keys
      ↓
Cloud secret managers
      ↓
HashiCorp Vault / enterprise secret management
```

---

# 50. Recommended Improvement: SSH Key Authentication

For the first lesson we use:

```text
SSH_USERNAME
SSH_PASSWORD
```

because it is easy to understand.

For a later lesson, replace the password with an SSH private key.

The secrets could become:

```text
SSH_HOST
SSH_USERNAME
SSH_PRIVATE_KEY
SSH_PORT
```

The public key is installed on the server.

The private key is stored in GitHub Secrets.

That provides a more production-like deployment approach.

---

# 51. Server Requirements

Before the deployment job can work, the server must have Docker installed.

For an Ubuntu server:

```bash
sudo apt update
sudo apt install docker.io -y
```

Enable Docker:

```bash
sudo systemctl enable docker
```

Start Docker:

```bash
sudo systemctl start docker
```

Verify:

```bash
docker --version
```

The deployment user should be able to execute Docker commands.

For a training environment:

```bash
sudo usermod -aG docker $USER
```

Log out and log back in.

Then verify:

```bash
docker ps
```

The command should run successfully.

---

# 52. Basic Troubleshooting

## `npm ci` fails

Check that the repository contains:

```text
package.json
package-lock.json
```

---

## `npm run build` fails

Run the same command locally:

```bash
npm run build
```

Fix the application build before expecting CI to succeed.

---

## Trivy fails the pipeline

Read the vulnerability table in GitHub Actions.

Look at:

```text
Package
Installed Version
Fixed Version
Severity
Vulnerability ID
```

Then determine whether to:

- upgrade the affected dependency,
- change the Docker base image,
- update the package,
- or document an accepted security exception.

Do not simply disable scanning because the pipeline failed.

---

## Docker login fails

Verify:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
```

Also verify that the Docker Hub access token has appropriate permissions.

---

## Docker push fails

Check that the Docker Hub repository exists or that your Docker Hub account is allowed to create/push to it.

Verify the image name:

```text
username/oge-portfoliofor
```

---

## SSH connection fails

Check:

```text
SSH_HOST
SSH_USERNAME
SSH_PASSWORD
SSH_PORT
```

Also check:

- firewall rules,
- cloud security groups,
- whether SSH is running,
- whether the user is allowed to login,
- whether the server accepts password authentication.

Test manually:

```bash
ssh username@server-ip
```

---

## `docker: permission denied`

The remote Linux user may not have permission to access Docker.

Check:

```bash
docker ps
```

If necessary:

```bash
sudo usermod -aG docker $USER
```

Then log out and log in again.

---

## Website is not reachable

Check whether the container is running:

```bash
docker ps
```

View logs:

```bash
docker logs oge-portfoliofor
```

Check port mapping:

```bash
docker port oge-portfoliofor
```

Also verify that port `80` is open in the server firewall or cloud security group.

---

# 53. Important DevSecOps Lessons from This Pipeline

This project demonstrates several important concepts.

### Continuous Integration

Every change is automatically checked.

```text
Install
Test
Lint
Build
```

### Security as Part of CI/CD

Security scanning happens automatically.

```text
Source Scan
Container Scan
```

### Security Gates

A critical vulnerability can stop deployment.

```text
Vulnerability
     ↓
Pipeline failure
     ↓
No deployment
```

### Secrets Management

Credentials are kept outside the repository.

```text
GitHub Secrets
```

### Containerization

The application is packaged into a Docker image.

```text
Application
+
Dependencies
+
Runtime
=
Docker Image
```

### Container Registry

Docker Hub stores application images.

```text
GitHub Actions
      ↓
Docker Hub
      ↓
Deployment Server
```

### Continuous Deployment

A successful pipeline automatically updates the server.

```text
Push to main
     ↓
Validate
     ↓
Scan
     ↓
Package
     ↓
Publish
     ↓
Deploy
```

---

# 54. Final Architecture

```text
                    Developer
                        |
                        |
                   git push main
                        |
                        v
                 +---------------+
                 |    GitHub     |
                 +---------------+
                        |
                        v
                 +---------------+
                 | GitHub Actions|
                 +---------------+
                        |
                        v
               +-------------------+
               |        CI         |
               | npm ci            |
               | npm test          |
               | npm lint          |
               | npm build         |
               +-------------------+
                        |
                        v
               +-------------------+
               |      Trivy        |
               | Filesystem Scan   |
               +-------------------+
                        |
                        v
               +-------------------+
               |   Docker Build    |
               +-------------------+
                        |
                        v
               +-------------------+
               |      Trivy        |
               | Docker Image Scan |
               +-------------------+
                        |
                        v
               +-------------------+
               |    Docker Hub     |
               +-------------------+
                        |
                        v
                  SSH Deployment
                        |
                        v
               +-------------------+
               | Deployment Server |
               |                   |
               | docker pull       |
               | docker stop       |
               | docker rm         |
               | docker run        |
               +-------------------+
                        |
                        v
                   Application
```

---

# 55. Summary

The pipeline follows this principle:

```text
CODE
 ↓
TEST
 ↓
BUILD
 ↓
SCAN
 ↓
PACKAGE
 ↓
SCAN AGAIN
 ↓
PUBLISH
 ↓
DEPLOY
```

The most important lesson is that deployment should not be treated as a single command.

A proper CI/CD pipeline creates controlled checkpoints.

In this project:

1. The application must build.
2. The repository must pass the vulnerability scan.
3. The Docker image must build.
4. The Docker image must pass its vulnerability scan.
5. Only then is the image pushed to Docker Hub.
6. Only after that does GitHub connect to the server.
7. The server pulls the exact image associated with the Git commit.
8. The old container is replaced by the new container.

This is a simple but realistic introduction to **CI/CD, Docker, vulnerability scanning, GitHub Secrets, and automated deployment**.
