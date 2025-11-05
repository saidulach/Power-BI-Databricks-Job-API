# API.m — Power Query (M) Databricks Job Runner

This document explains `API.m`, a Power Query (M) script that triggers an Azure Databricks job, polls its status until completion, and returns the notebook output for use in Power BI.

## Purpose
- Trigger a Databricks job remotely from Power BI (or Power Query) using the Databricks REST API.
- Poll the job run until it reaches a terminal state and then fetch the run output (for example, the notebook result).
- Return the notebook output as a Power Query table that can be used inside Power BI reports.

## File location
Place this file alongside `API.m` for reference. The script itself should be copied into Power BI Desktop via the Advanced Editor or a `.pq`/`.m` query.

## Prerequisites
- An Azure Databricks workspace and a job configured to run the desired notebook.
- A Databricks personal access token (PAT) with permission to run jobs.
- Power BI Desktop (or Power Query compatible environment).

Security note: Do not hard-code production tokens in queries. Use Power BI Parameters, Azure Key Vault, or other secure secret management solutions when possible.

## How it works (high level)
1. TriggerDatabricksJob: calls the Databricks `jobs/run-now` endpoint with the configured `jobId`. It returns a `run_id` for the triggered run.
2. PollJobStatus: repeatedly calls `jobs/runs/get` until the job's `life_cycle_state` becomes `TERMINATED`.
3. FetchOutput: calls `jobs/runs/get-output` to retrieve the notebook output for the completed run.
4. The script returns the notebook output's `result` field (you may need to adjust this depending on what your notebook returns).

## Script parameters / placeholders
Inside the script there are placeholders you should replace or expose as Power BI parameters:
- `{your_server}` — your Databricks workspace hostname (e.g. `adb-123456789012345.11.azuredatabricks.net`).
- `{your_key}` — your Databricks personal access token (PAT).
- `jobId` — the numeric Databricks job ID to trigger (e.g. `123456`).

Example of defining Power Query parameters instead of editing the file directly:
- Create parameters `DatabricksServer`, `DatabricksToken`, `DatabricksJobId` in Power BI.
- Replace the placeholders in the query with those parameter names.

## Important implementation details from the script
- Web.Contents usage:
  - For `jobs/run-now` the script calls the full URL directly ("https://{your_server}.azuredatabricks.net/api/2.0/jobs/run-now/").
  - For `jobs/runs/get` and `jobs/runs/get-output` the script uses `Web.Contents` with a `testUrl` and a `RelativePath`. This pattern is used to avoid issues with Power BI Service when calling `Web.Contents`.
- The script sets `IsRetry=true` for some requests to allow Power Query to retry transient failures.
- Polling is implemented with `Function.InvokeAfter(() => @PollJobStatus(run_id), #duration(0, 0, 0, 10))` which waits 10 seconds between checks.

## Function reference (from the script)
- TriggerDatabricksJob() : triggers the job and returns the `run_id`.
- CheckJobStatus(run_id as number) : returns the `life_cycle_state` (string) for the given run.
- FetchOutput(run_id as number) : returns the JSON response from `jobs/runs/get-output`.
- PollJobStatus(run_id as number) : recursively polls `CheckJobStatus` until `TERMINATED`, then returns `FetchOutput(run_id)`.

## Typical usage (in Power BI Desktop)
1. Open Power BI Desktop.
2. Home -> Get Data -> Blank Query.
3. Open Advanced Editor.
4. Replace the placeholders in the script (`{your_server}`, `{your_key}`, `jobId`) or reference Power BI parameters.
5. Save & Close. The query will execute and return the notebook output as a table.

Example parameter usage (recommended):
- Create three parameters in Power Query: `DatabricksServer`, `DatabricksToken`, `DatabricksJobId`.
- Edit the script to reference these parameters:
  - `testUrl = "https://" & DatabricksServer & ".azuredatabricks.net"`
  - `Authorization = "Bearer " & DatabricksToken`
  - `jobId = DatabricksJobId`

## Output handling
- The script currently returns `notebook_output[result]`. This assumes your notebook writes a JSON structure with a `result` field. Adjust this path to match your notebook's returned payload.
- If your notebook writes files or uses DBFS output, you may need to modify the `FetchOutput` handling to return the correct field(s) (for example `notebook_output[notebook_output][0]`, or inspect the full `jsonOutput` result first).

## Example adjustments
- To return the entire JSON output for inspection, change the final return to `jsonOutput` (or `output`) instead of `notebook_output[result]`.
- To slow down polling, increase the duration in `Function.InvokeAfter` (e.g., `#duration(0,0,0,30)` for 30s).

## Troubleshooting
- 401 Unauthorized:
  - Verify the PAT is correct and not expired.
  - Ensure the token has the right permissions to run jobs.
- 404 Not Found / Bad endpoint:
  - Verify the `server` hostname and the REST endpoint paths.
  - Make sure `jobId` exists in the workspace.
- Power BI fails to send custom Authorization header when using scheduled refresh:
  - Use Power BI service credentials settings or a secure parameter for the token.
  - If using the Power BI Service, ensure the dataset credentials are configured and that the service supports the required header usage.
- Polling recursion errors or timeouts:
  - Increase the polling interval or add a maximum retry/timeout guard in `PollJobStatus` to avoid infinite recursion.

## Enhancements and security best practices
- Don't hard-code tokens. Use Power BI Parameters or Azure Key Vault where possible.
- Add a maximum attempt count to `PollJobStatus` to avoid indefinite polling.
- Add better error checking: after each `Web.Contents` call, check for an HTTP error status and handle it gracefully.
- Consider storing `jobId` and related configuration in a parameterized configuration table so multiple jobs can be triggered by changing a single parameter or a table row.

## Example: Add a basic timeout guard to `PollJobStatus`
Replace the simple recursive call with a version that accepts `attempt` and `maxAttempts`:

- Pseudocode idea:
  - `PollJobStatus = (run_id as number, attempt as number) => if attempt > 60 then error "timeout" else ... Function.InvokeAfter(() => @PollJobStatus(run_id, attempt+1), #duration(0,0,0,10))`

## Notes about Power BI Service
- When publishing to the Power BI Service and scheduling refreshes:
  - Store the Databricks token securely via dataset parameters or a linked service like Key Vault.
  - If Power BI reports errors on `Web.Contents`, check the privacy level settings, connection credentials and whether a gateway is required.
