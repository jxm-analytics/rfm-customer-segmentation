CREATE DATABASE CustomerRFM;
GO

USE CustomerRFM;
GO

CREATE TABLE Transactions (
    InvoiceNo VARCHAR(20),
    StockCode VARCHAR(20),
    Description VARCHAR(100),
    Quantity INT,
    InvoiceDate VARCHAR(25), 
    UnitPrice DECIMAL(10,2),
    CustomerID INT,
    Country VARCHAR(50)
);

BULK INSERT dbo.Transactions
FROM 'C:\Temp\Online Retail.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);

SELECT COUNT(*) AS total_rows FROM dbo.Transactions;

SELECT TOP 5 * FROM dbo.Transactions;

ALTER TABLE Transactions
ALTER COLUMN InvoiceDate DATETIME;


SELECT *
into TransactionsCleaned
FROM dbo.Transactions
WHERE 
    CustomerID IS NOT NULL
    AND Quantity > 0
    AND UnitPrice > 0
    AND Description IS NOT NULL
    AND LEN(RTRIM(LTRIM(InvoiceNo))) > 0
	AND InvoiceNo not like 'C%'
	and StockCode not in ('D',	'C2',	'DOT',	'M',	'BANK CHARGES',	'S',	'AMAZONFEE',	'PADS',	'B',	'CRUK')

with cte as (select *, ROW_NUMBER() over (partition by InvoiceNO, StockCode,[Description],Quantity,InvoiceDate,UnitPrice,CustomerID, Country  ORDER BY (SELECT NULL)) as rn from Transactions)
delete from cte where rn>1;

-- How recently did each customer make a purchase?
select CustomerID, DATEDIFF(day,max(InvoiceDate),'2011-12-09') DaysSinceLastPurchase from TransactionsCleaned group by CustomerID;

--  2. “How often did the customer make purchases?”
select customerid, count(distinct invoiceno) as InvoiceCount from TransactionsCleaned group by CustomerID;

--3.How much money did the customer spend in total?
select CustomerID, sum(Unitprice*Quantity) AS TotalSpent from TransactionsCleaned group by CustomerID;

-- 4. Combine All Three
with crp as (
	select CustomerID, DATEDIFF(day,max(InvoiceDate),'2011-12-09') Recency 
	from TransactionsCleaned group by CustomerID),

cop as (
	select customerid, count(distinct invoiceno) as Frequency 
	from TransactionsCleaned group by CustomerID),
cmp as (
	select CustomerID, sum(Unitprice*Quantity) AS Monetary 
	from TransactionsCleaned group by CustomerID
	)
select crp.CustomerID,crp.Recency,cop.Frequency,cmp.Monetary
into RFMbase
from crp join cop on crp.CustomerID=cop.CustomerID 
join cmp on cmp.CustomerID=cop.CustomerID;

SELECT
  CustomerID,
  Recency,
  Frequency,
  Monetary,
  6 - NTILE(5) OVER (ORDER BY Recency ASC) AS RecencyScore,
  NTILE(5) OVER (ORDER BY Frequency ASC) AS FrequencyScore,
  NTILE(5) OVER (ORDER BY Monetary ASC) AS MonetaryScore
FROM RFMBase;

WITH RFM_Coded AS (
  SELECT 
    CustomerID,
    CAST(RecencyScore AS VARCHAR) 
      + CAST(FrequencyScore AS VARCHAR) 
      + CAST(MonetaryScore AS VARCHAR) AS RFMCode
  FROM (SELECT
  CustomerID,
  Recency,
  Frequency,
  Monetary,
  6 - NTILE(5) OVER (ORDER BY Recency ASC) AS RecencyScore,
  NTILE(5) OVER (ORDER BY Frequency ASC) AS FrequencyScore,
  NTILE(5) OVER (ORDER BY Monetary ASC) AS MonetaryScore
FROM RFMBase) as scored
)

SELECT 
  CustomerID,
  RFMCode,
  CASE
    WHEN RFMCode = '555' THEN 'Champion'
    WHEN RFMCode LIKE '_5_' OR RFMCode LIKE '_4_' THEN 'Loyal Customer'
    WHEN RFMCode LIKE '__5' OR RFMCode LIKE '__4' THEN 'Big Spender'
    WHEN RFMCode LIKE '5__' THEN 'New Customer'
    WHEN RFMCode LIKE '1__' THEN 'At Risk'
    WHEN RFMCode LIKE '1_5' THEN 'Can’t Lose Them'
    WHEN RFMCode = '111' THEN 'Lost'
    ELSE 'Others'
  END AS SegmentName
into RFM_Segments
FROM RFM_Coded;
