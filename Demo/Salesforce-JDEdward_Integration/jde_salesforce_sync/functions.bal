import ballerina/log;
import ballerinax/salesforce;

function orderHasItems(string orderId) returns boolean|error {
    string soql = string `SELECT Id FROM OrderItem WHERE OrderId = '${orderId}' LIMIT 1`;
    stream<record {|anydata...;|}, error?> resultStream = check salesforceClient->query(soql);
    record {|anydata...;|}[] results = check from record {|anydata...;|} rec in resultStream select rec;
    return results.length() > 0;
}

function syncJdeOrdersToSalesforce() returns error? {
    string filterQuery = "$filter=F4211.DCTO%20EQ%20SO&$filter=F4211.USER%20EQ%20JDE";
    json response = check getTable("F4211", filterQuery);

    json browseData = check response.fs_DATABROWSE_F4211;
    json dataSection = check browseData.data;
    json gridData = check dataSection.gridData;
    json rowsetJson = check gridData.rowset;

    json[] rowsetArray = check rowsetJson.cloneWithType();
    F4211Row[] allRows = from json rowJson in rowsetArray
        select check rowJson.cloneWithType(F4211Row);

    map<F4211Row[]> groupedRows = {};
    int[] distinctOrderNumbers = [];
    map<boolean> seenOrders = {};
    foreach F4211Row jdeRow in allRows {
        string orderKey = jdeRow.F4211_DOCO.toString();
        F4211Row[] existingRows = groupedRows[orderKey] ?: [];
        existingRows.push(jdeRow);
        groupedRows[orderKey] = existingRows;
        if !seenOrders.hasKey(orderKey) {
            seenOrders[orderKey] = true;
            distinctOrderNumbers.push(jdeRow.F4211_DOCO);
        }
    }

    log:printInfo("Grouped JDE orders", orderCount = groupedRows.length());

    int[] sortedAscending = distinctOrderNumbers.sort();
    int totalOrders = sortedAscending.length();
    int startIndex = totalOrders > jdeLastNOrders ? totalOrders - jdeLastNOrders : 0;
    int[] lastNOrderNumbers = sortedAscending.slice(startIndex);

    log:printInfo("Processing last N JDE orders", requestedCount = jdeLastNOrders, actualCount = lastNOrderNumbers.length());

    foreach int orderNum in lastNOrderNumbers {
        string orderKey = orderNum.toString();
        F4211Row[] orderRows = groupedRows.get(orderKey);
        string orderId = check upsertJdeOrderHeader(orderRows);
        boolean alreadyHasItems = check orderHasItems(orderId);
        if alreadyHasItems {
            log:printInfo("Order already synced, skipping items", jdeOrderNumber = orderKey, salesforceOrderId = orderId);
        } else {
            check createOrderItemsForOrder(orderId, orderRows);
            check activateOrder(orderId);
            log:printInfo("Synced JDE order to Salesforce", jdeOrderNumber = orderKey, salesforceOrderId = orderId);
        }
    }
}

function getStandardPricebookId() returns string|error {
    string soql = "SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1";
    stream<record {|anydata...;|}, error?> resultStream = check salesforceClient->query(soql);
    record {|anydata...;|}[] results = check from record {|anydata...;|} rec in resultStream select rec;
    if results.length() == 0 {
        return error("No Standard Pricebook found in this org");
    }
    IdOnly pb = check results[0].cloneWithType(IdOnly);
    return pb.Id;
}

function upsertJdeOrderHeader(F4211Row[] orderRows) returns string|error {
    F4211Row headerRow = orderRows[0];
    string accountId = check getAccountIdByJdeCustomerNumber(headerRow.F4211_AN8);
    string pricebookId = check getStandardPricebookId();
    string jdeDate = headerRow.F4211_TRDJ;
    string effectiveDate = string `${jdeDate.substring(0, 4)}-${jdeDate.substring(4, 6)}-${jdeDate.substring(6, 8)}`;
    string orderNumber = headerRow.F4211_DOCO.toString();

    IdOnly|error existing = salesforceClient->getByExternalId("Order", "JDE_Order_Number__c", orderNumber, returnType = IdOnly);
    if existing is IdOnly {
        record {|anydata...;|} updateFields = {
            "AccountId": accountId,
            "Pricebook2Id": pricebookId,
            "EffectiveDate": effectiveDate
        };
        check salesforceClient->update("Order", existing.Id, updateFields);
        log:printInfo("Updated existing Salesforce Order", orderId = existing.Id, jdeOrderNumber = orderNumber);
        return existing.Id;
    }

    record {|anydata...;|} newOrderFields = {
        "AccountId": accountId,
        "Pricebook2Id": pricebookId,
        "EffectiveDate": effectiveDate,
        "Status": "Draft",
        "JDE_Order_Number__c": orderNumber
    };
    salesforce:CreationResponse created = check salesforceClient->create("Order", newOrderFields);
    log:printInfo("Created new Salesforce Order", orderId = created.id, jdeOrderNumber = orderNumber);
    return created.id;
}

function createOrderItemsForOrder(string orderId, F4211Row[] orderRows) returns error? {
    foreach F4211Row lineRow in orderRows {
        string pricebookEntryId = check getPricebookEntryIdByProductCode(lineRow.F4211_LITM);
        record {|anydata...;|} orderItemFields = {
            "OrderId": orderId,
            "PricebookEntryId": pricebookEntryId,
            "Quantity": lineRow.F4211_UORG,
            "UnitPrice": lineRow.F4211_UPRC
        };
        salesforce:CreationResponse created = check salesforceClient->create("OrderItem", orderItemFields);
        log:printInfo("Created Salesforce OrderItem", orderItemId = created.id, jdeItemCode = lineRow.F4211_LITM, quantity = lineRow.F4211_UORG);
    }
}

function activateOrder(string orderId) returns error? {
    record {|anydata...;|} statusUpdate = {
        "Status": "Activated"
    };
    check salesforceClient->update("Order", orderId, statusUpdate);
    log:printInfo("Activated Salesforce Order", orderId = orderId);
}

function getPricebookEntryIdByProductCode(string productCode) returns string|error {
    string soql = string `SELECT Id FROM PricebookEntry WHERE Product2.ProductCode = '${productCode}' AND Pricebook2.IsStandard = true AND IsActive = true`;
    stream<record {|anydata...;|}, error?> resultStream = check salesforceClient->query(soql);
    record {|anydata...;|}[] results = check from record {|anydata...;|} rec in resultStream select rec;
    if results.length() == 0 {
        return error(string `No active Standard Pricebook entry found for product code ${productCode}`);
    }
    IdOnly entry = check results[0].cloneWithType(IdOnly);
    return entry.Id;
}

function getJdeCustomerNumberByAccountId(string accountId) returns string|error {
    string soql = string `SELECT JDE_Customer_Number__c FROM Account WHERE Id = '${accountId}'`;
    stream<record {|anydata...;|}, error?> resultStream = check salesforceClient->query(soql);
    record {|anydata...;|}[] results = check from record {|anydata...;|} rec in resultStream select rec;
    if results.length() == 0 {
        return error(string `Account ${accountId} not found`);
    }
    json accountJson = results[0].toJson();
    json jdeCustomerNumberJson = check accountJson.JDE_Customer_Number__c;
    if jdeCustomerNumberJson == () {
        return error(string `Account ${accountId} has no JDE_Customer_Number__c set — cannot push order to JDE`);
    }
    return jdeCustomerNumberJson.toString();
}

function buildJdeOrderRequest(CombinedOrder 'order) returns JdeSalesOrderRequest|error {
    string customerNumber = check getJdeCustomerNumberByAccountId('order.AccountId);
    JdeSalesOrderLine[] lines = from OrderLine line in 'order.lines
        select {quantityOrdered: line.Quantity, itemNumber: line.ProductCode};
    return {businessUnit: "30", customerNumber, lines};
}

function getAccountIdByJdeCustomerNumber(int customerNumber) returns string|error {
    string soql = string `SELECT Id FROM Account WHERE JDE_Customer_Number__c = '${customerNumber}'`;
    stream<record {|anydata...;|}, error?> resultStream = check salesforceClient->query(soql);
    record {|anydata...;|}[] results = check from record {|anydata...;|} rec in resultStream select rec;
    if results.length() == 0 {
        return error(string `No Salesforce Account found for JDE customer number ${customerNumber}`);
    }
    IdOnly account = check results[0].cloneWithType(IdOnly);
    return account.Id;
}
