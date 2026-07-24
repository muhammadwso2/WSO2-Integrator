import ballerina/log;
import ballerinax/salesforce;

listener salesforce:Listener salesforceListener = new (listenerConfig = {auth: {username: sfUsername, password: sfPasswordWithToken}});

service "/data/OrderChangeEvent" on salesforceListener {
    remote function onCreate(salesforce:EventData payload) returns error|() {
        do {
            log:printInfo("Salesforce Order created", payload = payload.toString());
        } on fail error err {
            // handle error
            return error("unhandled error", err);
        }
    }

    remote function onUpdate(salesforce:EventData payload) returns error|() {
        do {
            log:printInfo("Salesforce Order updated", payload = payload.toString());
            salesforce:ChangeEventMetadata? eventMetadata = payload.metadata;
            string recordId = eventMetadata is salesforce:ChangeEventMetadata ? (eventMetadata.recordId ?: "") : "";

            if payload.changedData["Status"] != "Activated" {
                return;
            }
            if recordId == "" {
                return;
            }

            stream<record {|anydata...;|}, error?> orderStream = check salesforceClient->query(
                string `SELECT Id, OrderNumber, Status, EffectiveDate, TotalAmount, AccountId, Account.Name, JDE_Order_Number__c FROM Order WHERE Id = '${recordId}'`
            );
            record {|anydata...;|}[] orderResults = check from record {|anydata...;|} orderRecord in orderStream
                select orderRecord;
            json orderJson = orderResults[0].toJson();
            json jdeOrderNumberJson = check orderJson.JDE_Order_Number__c;
            if jdeOrderNumberJson != () {
                log:printInfo("Order originated from JDE, skipping push back to JDE", orderId = recordId, jdeOrderNumber = jdeOrderNumberJson.toString());
                return;
            }
            stream<record {|anydata...;|}, error?> orderItemStream = check salesforceClient->query(
                string `SELECT Id, Quantity, UnitPrice, PricebookEntry.Product2.ProductCode, PricebookEntry.Product2.Name FROM OrderItem WHERE OrderId = '${recordId}'`
            );
            record {|anydata...;|}[] orderItemResults = check from record {|anydata...;|} orderItemRecord in orderItemStream
                select orderItemRecord;
            OrderLine[] orderLines = from record {|anydata...;|} itemRow in orderItemResults
                let json itemJson = itemRow.toJson()
                select {
                    Id: (check itemJson.Id).toString(),
                    Quantity: check decimal:fromString((check itemJson.Quantity).toString()),
                    UnitPrice: check decimal:fromString((check itemJson.UnitPrice).toString()),
                    ProductCode: (check itemJson.PricebookEntry.Product2.ProductCode).toString(),
                    ProductName: (check itemJson.PricebookEntry.Product2.Name).toString()
                };
            CombinedOrder combinedOrder = {
                Id: (check orderJson.Id).toString(),
                OrderNumber: (check orderJson.OrderNumber).toString(),
                Status: (check orderJson.Status).toString(),
                EffectiveDate: (check orderJson.EffectiveDate).toString(),
                TotalAmount: check decimal:fromString((check orderJson.TotalAmount).toString()),
                AccountId: (check orderJson.AccountId).toString(),
                AccountName: (check orderJson.Account.Name).toString(),
                lines: orderLines
            };
            JdeSalesOrderRequest jdeOrderRequest = check buildJdeOrderRequest(combinedOrder);
            json jdeResponse = check callSalesOrderCreateOrchestration(jdeOrderRequest);
            log:printInfo("Pushed Salesforce order to JDE", salesforceOrderId = recordId, jdeResponse = jdeResponse.toString());
        } on fail error err {
            // handle error
            return error("unhandled error", err);
        }
    }

    remote function onDelete(salesforce:EventData payload) returns error|() {
        do {
        } on fail error err {
            // handle error
            return error("unhandled error", err);
        }
    }

    remote function onRestore(salesforce:EventData payload) returns error|() {
        do {
        } on fail error err {
            // handle error
            return error("unhandled error", err);
        }
    }
}
