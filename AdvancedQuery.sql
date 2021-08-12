DECLARE @account BIGINT = 62--[AccountID]
DECLARE @Status VARCHAR(10) ='Completed'
DECLARE @BillHolidayMultiplier VARCHAR(10) =''
DECLARE @BillOTHours VARCHAR(10) =''
DECLARE @Mileage VARCHAR(10) =''
DECLARE @MileageRate VARCHAR(10) =''
DECLARE @Date DATETIME = CONVERT(DATE, Getutcdate())
DECLARE @Timezone TINYINT = 0
DECLARE @DST BIT = 0
DECLARE @inDST TINYINT = 0

SELECT @Timezone = timezone,
       @DST = s.indst
FROM   schedule s
WHERE  s.accountid = @account

SET @date = Dateadd (hh, -1 * @Timezone, @date)

IF @DST = 1
  BEGIN
      SELECT @inDST = 1
      FROM   daylightsaving
      WHERE  Year(@Date) = [year]
             AND [begin] <= @Date
             AND [end] >= @Date

      SET @date = Dateadd (hh, @inDST, @date)
  END

PRINT @Date

DECLARE @OffSet SMALLINT = @TimeZone - @inDST

PRINT @OffSet

SELECT --s.[AccountID]
--,sch.scheduleid
Format(i.invoicedate, 'MM/dd/yyyy')            AS 'Invoice Date',
i.invoiceno                                    AS 'Invoice ID',
SCHEDINFO.[client name],
SCHEDINFO.[caregiver name],
Concat(s.servicename, ' - ', a.activityname)   AS 'Bill Rate Name',
CASE
  WHEN SCHEDINFO.ratetype = 1 THEN 'Hourly'
  WHEN SCHEDINFO.ratetype = 2 THEN 'Visit'
  WHEN SCHEDINFO.ratetype = 3 THEN 'Unit'
  WHEN SCHEDINFO.ratetype = 4 THEN 'Per Diem'
  ELSE ''
END                                            AS 'Bill Method',
SCHEDINFO.[official clock in]
--,SCHEDINFO.[ItemDate]
,
SCHEDINFO.[official clock out],
COALESCE(NULL, @Status)                        AS [Status],
COALESCE(NULL, @BillHolidayMultiplier)         AS [Bill Holiday Multiplier],
COALESCE(NULL, @BillOTHours)                   AS [Bill OT Hours],
COALESCE(NULL, @Mileage)                       AS [Mileage],
COALESCE(NULL, @MileageRate)                   AS [Mileage Rate],
SCHEDINFO."rate"                               AS [Bill Rate Amount],
Format(SCHEDINFO.[bill regular hours], '#.00') AS [Bill Regular Hours]
--in the future will be sum of regular hours plus OT + Holiday
,
SCHEDINFO.[bill total]
--,S_TIME.IsOvernight
FROM   [vincent].[dbo].[schedule] sch
       LEFT OUTER JOIN (SELECT
                                             s.accountid,
                               s.scheduleid,
                               (SELECT TOP 1 schi.ratetype
                                FROM   scheduleitem schi
                                WHERE  schi.accountid = @account
                                       AND schi.scheduleid = s.scheduleid) AS
                                                             [RateType],
                               ii.invoiceid,
                               Sum(ii.amount)                              AS
                                                             [Bill Total],
                               CASE
                                 WHEN sct.timeinr IS NOT NULL
                                      AND id.itemdate > sct.timeinr THEN
                                 Format(id.itemdate, 'MM/dd/yyyy hh:mm tt')
                                 WHEN sct.timeinr IS NOT NULL THEN Format(
                                 Dateadd(hh, -1 * @OffSet,
                                 sct.timeinr), 'MM/dd/yyyy hh:mm tt')
                                 WHEN id.itemdate > s.timeind THEN
                                 Format(id.itemdate, 'MM/dd/yyyy hh:mm:tt')
                                 ELSE Format(s.timeind, 'MM/dd/yyyy hh:mm:tt')
                               END                                         AS
                                                             [Official Clock In]
                                             ,
       CASE
         WHEN sct.timeoutr IS NOT NULL
              AND id.itemdate < CONVERT(DATE, sct.timeoutr)
                     THEN
         Format(CONVERT(DATETIME, id.itemdate) + '23:59:59',
         'MM/dd/yyyy hh:mm tt')
         WHEN sct.timeoutr IS NOT NULL THEN Format(
         Dateadd(hh, -1 * @OffSet,
         sct.timeoutr), 'MM/dd/yyyy hh:mm tt')
         WHEN id.itemdate < CONVERT(DATE, s.timeoutd) THEN
         Format(
         CONVERT(DATETIME, id.itemdate) + '23:59:59',
         'MM/dd/yyyy hh:mm tt')
         ELSE Format(s.timeoutd, 'MM/dd/yyyy hh:mm tt')
       END                                         AS
                     [Official Clock Out],
       id.itemdate,
       id.quantity                                 AS
                     [Bill Regular Hours],
       Concat(C.firstname, ' ', C.lastname)        AS
                     [Client Name],
       Concat(ST.firstname, ' ', ST.lastname)      AS
                     [CAREGiver Name],
       (SELECT TOP 1 schi.rate
        FROM   scheduleitem schi
        WHERE  schi.accountid = @account
               AND schi.scheduleid = s.scheduleid) AS 'Rate'
                        FROM   schedule s
                               INNER JOIN scheduleitem si
                                       ON si.scheduleid = s.scheduleid
                                          AND si.accountid = @account
                               LEFT OUTER JOIN invoiceitem ii
                                            ON ii.invoiceitemid =
                                               si.invoiceitemid
                                               AND ii.accountid = @account
                               INNER JOIN invoicedetail id
                                       ON ii.invoiceitemid = id.invoiceitemid
                                          AND ii.invoiceid = id.invoiceid
                                          AND id.accountid = ii.accountid
                               INNER JOIN client c
                                       ON c.clientid = s.clientid
                                          AND c.accountid = @account
                               LEFT OUTER JOIN staff st
                                            ON st.staffid = s.staffid
                                               AND s.accountid = @account
                               LEFT OUTER JOIN scheduletime sct
                                            ON sct.scheduleid = s.scheduleid
                                               AND sct.accountid = @account
                        GROUP  BY s.accountid,
                                  s.scheduleid,
                                  ii.invoiceid,
                                  c.firstname,
                                  c.lastname,
                                  st.firstname,
                                  st.lastname,
                                  sct.scheduleid,
                                  sct.timeinr,
                                  s.timeind,
                                  sct.timeoutr,
                                  s.timeoutd,
                                  id.quantity,
                                  id.itemdate) AS SCHEDINFO
                    ON sch.scheduleid = SCHEDINFO.scheduleid
                       AND SCHEDINFO.accountid = @account
       INNER JOIN invoice i
               ON i.accountid = SCHEDINFO.accountid
                  AND i.invoiceid = SCHEDINFO.invoiceid
       INNER JOIN activity a
               ON a.accountid = SCHEDINFO.accountid
                  AND a.activitycode = sch.activitycode
       INNER JOIN [vincent].[dbo].[service] s
               ON s.accountid = SCHEDINFO.accountid
                  AND s.servicecode = sch.servicecode
       INNER JOIN payor p
               ON p.accountid = i.accountid
                  AND p.payorid = i.payorid
       LEFT OUTER JOIN scheduletime sct
                    ON sct.scheduleid = sch.scheduleid
       OUTER apply (SELECT s.accountid,
                           s.scheduleid,
                           CASE
                             WHEN Datepart(d, s.timeind) <
                                  Datepart(d, s.timeoutd) THEN
                             '1'
                             ELSE '0'
                           END AS [IsOvernight]
                    FROM   schedule s
                           LEFT OUTER JOIN scheduletime st
                                        ON st.accountid = s.accountid
                                           AND st.scheduleid = s.scheduleid
                    WHERE  s.accountid = @account
                           AND sch.scheduleid = s.scheduleid) AS S_TIME
WHERE  sch.accountid = @account
       AND sch.status IN ( 2, 6 )
       AND i.status <> 3 --and s_time.IsOvernight = '1'
