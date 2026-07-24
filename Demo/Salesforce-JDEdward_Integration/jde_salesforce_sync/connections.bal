import ballerina/http;
import ballerinax/salesforce;

configurable string sfBaseUrl = ?;
configurable string sfTokenUrl = ?;
configurable string sfClientId = ?;
configurable string sfClientSecret = ?;
configurable string sfUsername = ?;
configurable string sfPasswordWithToken = ?;

configurable string jdeBaseUrl = ?;
configurable string jdeUser = ?;
configurable string jdePass = ?;
configurable string jdeEnv = ?;
configurable string jdeRole = ?;
configurable int jdeLastNOrders = 3;

final salesforce:Client salesforceClient = check new ({
    baseUrl: sfBaseUrl,
    auth: {
        tokenUrl: sfTokenUrl,
        clientId: sfClientId,
        clientSecret: sfClientSecret
    }
});
final http:Client jdeClient = check new (string `${jdeBaseUrl}`, secureSocket = {
    enable: false
});
