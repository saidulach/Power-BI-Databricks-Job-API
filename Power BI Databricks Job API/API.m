let
    Source = let

    jobId = [your jobId] // ex : jobID = 123456,

    // Function to trigger Databricks job
    TriggerDatabricksJob = () =>
        let
            // Construct request body
            requestBody = [
                job_id = jobId
                               
            ],
            requestBodyJson = Json.FromValue(requestBody),
            response = Web.Contents(
                "https://{your_server}.azuredatabricks.net/api/2.0/jobs/run-now/",
                [
                    Headers = [
                        Authorization = "Bearer {your_key}",
                        #"Content-Type" = "application/json"
                    ],
                    Content = requestBodyJson
                ]
            ),
            jsonResponse = Json.Document(response),
            run_id = jsonResponse[run_id]
        in
            run_id,
 
    // Function to check Databricks job status
    CheckJobStatus = (run_id as number) =>
        let
            testUrl = "https://{your_server}.azuredatabricks.net",
            response = Web.Contents(testUrl, 
                [
                    RelativePath = "api/2.0/jobs/runs/get", // breaking it here to make it work in powerbi service
                    Query = [
                            run_id=Number.ToText(run_id)
                    ],
                    Headers=[
                                Authorization="Bearer {your_key}"
                            ],IsRetry=true]),
            jsonResponse = Json.Document(response),
            status = jsonResponse[state][life_cycle_state]
        in
            status,
 
    // Function to fetch output from Databricks
    FetchOutput = (run_id as number) =>
        let
            testUrl = "https://{your_server}.azuredatabricks.net",
            response = Web.Contents(testUrl, 
                [
                    RelativePath = "api/2.0/jobs/runs/get-output",
                    Query = [
                            run_id=Number.ToText(run_id)
                    ],
                    Headers=[
                                Authorization="Bearer {your_key}"],
                            IsRetry=true]),
            jsonOutput = Json.Document(response)
        in
            jsonOutput,
 
   // Function to continuously check job status
    PollJobStatus = (run_id as number) =>
        let
            status = CheckJobStatus(run_id)
        in
            if status <> "TERMINATED" then
                // Recursive call after a delay
                Function.InvokeAfter(() => @PollJobStatus(run_id), #duration(0, 0, 0, 10))
            else
                FetchOutput(run_id),
 
    // Trigger Databricks job
    runId = TriggerDatabricksJob(),
 
    // Start polling job status
    output = PollJobStatus(runId),
    // Start polling job status
    notebook_output = output[notebook_output]
in
    notebook_output[result], //this part you have to adjust basis what you are returning in your notebook
    #"Converted to Table" = #table(1, {{Source}}),
    #"Renamed Columns" = Table.RenameColumns(#"Converted to Table",{{"Column1", "Status"}})
in
    #"Renamed Columns"