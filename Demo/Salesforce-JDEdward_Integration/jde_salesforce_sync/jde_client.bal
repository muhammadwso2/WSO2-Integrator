import ballerina/http;
import ballerina/log;

string? cachedToken = ();

function getJdeToken() returns string|error {
    string? currentToken = cachedToken;
    if currentToken is string {
        return currentToken;
    }

    string credentials = jdeUser + ":" + jdePass;
    string basicAuth = "Basic " + credentials.toBytes().toBase64();

    http:Response res = check jdeClient->get("/jderest/v3/orchestrator/jde-login", {
        "Authorization": basicAuth,
        "jde-AIS-Auth-Environment": jdeEnv,
        "jde-AIS-Auth-Role": jdeRole
    });

    json body = check res.getJsonPayload();
    json tokenJson = check body.userInfo.token;
    string token = tokenJson.toString();
    cachedToken = token;
    log:printInfo("JDE token retrieved", token = cachedToken);
    return token;
}

function callSalesOrderCreateOrchestration(JdeSalesOrderRequest orderRequest) returns json|error {
    string jdeToken = check getJdeToken();

    json[] itemList = from JdeSalesOrderLine line in orderRequest.lines
    select {
        "Quantity Ordered": line.quantityOrdered,
        "Item Number": line.itemNumber
    };

    json payload = {
        "Business Unit": orderRequest.businessUnit,
        "Customer Number": orderRequest.customerNumber,
        "Item List": itemList   
    };

    http:Response res = check jdeClient->post("/jderest/v3/orchestrator/Enter%20Sales%20Order",
        payload,
        headers = {
            "jde-AIS-Auth": jdeToken,
            "Content-Type": "application/json"
        }
    );

    json responseBody = check res.getJsonPayload();
    log:printInfo("JDE Sales Order created", response = responseBody.toString());
    return responseBody;
}

function getTable(string tableName, string? queryParams = ()) returns json|error {
    string jdeToken = check getJdeToken();

    string path = "/jderest/v2/dataservice/table/" + tableName;
    if queryParams is string {
        path = path + "?" + queryParams;
    }

    http:Response res = check jdeClient->get(path, {
        "jde-AIS-Auth": jdeToken
    });

    return check res.getJsonPayload();
}