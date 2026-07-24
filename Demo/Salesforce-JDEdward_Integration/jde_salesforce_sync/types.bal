type JdeSalesOrderLine record {|
    decimal quantityOrdered;
    string itemNumber;
|};

type JdeSalesOrderRequest record {|
    string businessUnit;
    string customerNumber;
    JdeSalesOrderLine[] lines;
|};

type OrderLine record {|
    string Id;
    decimal Quantity;
    decimal UnitPrice;
    string ProductCode;
    string ProductName;
|};

type CombinedOrder record {|
    string Id;
    string OrderNumber;
    string Status;
    string EffectiveDate;
    decimal TotalAmount;
    string AccountId;
    string AccountName;
    OrderLine[] lines;
|};

type F4211Row record {
    int F4211_DOCO;
    string F4211_MCU;
    int F4211_AN8;
    string F4211_LITM;
    decimal F4211_UORG;
    decimal F4211_UPRC;
    string F4211_TRDJ;
};

type IdOnly record {
    string Id;
};
