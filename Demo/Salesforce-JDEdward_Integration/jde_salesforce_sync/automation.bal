import ballerina/log;

public function main() returns error? {
    do {
        
        // temporary: test JDE login and log the token
        // string jdeToken = check getJdeToken();
        // log:printInfo("JDE token retrieved", token = jdeToken);

        // temporary: test Sales Order Create orchestration
        // JdeSalesOrderRequest testOrder = {
            // businessUnit: "30",
            // customerNumber: "4242",
            // lines: [
                // {quantityOrdered: 1, itemNumber: "220"},
                // {quantityOrdered: 2, itemNumber: "221"},
                // {quantityOrdered: 3, itemNumber: "222"}
            // ]
        // };
        // json jdeResponse = check callSalesOrderCreateOrchestration(testOrder);
        // log:printInfo("JDE Sales Order response", response = jdeResponse.toString());

        check syncJdeOrdersToSalesforce();

        // stream<record {|anydata...;|}, error?> streamReturntypeError = check salesforceClient->query("SELECT Id, OrderNumber, Status, TotalAmount FROM Order");
        // record {|anydata...;|}[] queryResults = check from record {|anydata...;|} orderRecord in streamReturntypeError
            // select orderRecord;
        // log:printInfo("Salesforce query results", results = queryResults.toString());

        
    } on fail error e {
        log:printError("Error occurred", 'error = e);
        return e;
    }
}
