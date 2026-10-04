# Order service: storage design (sample spec for spike S2)

## 1. Problem

Orders are lost when the single database server fails. We need orders to survive a data-centre outage.

## 2. Storage

2.1 All orders are stored in one Postgres database.
2.2 The database runs on one large server in data centre A.
2.3 A replica in data centre B receives changes every 5 minutes.
2.4 If data centre A fails, an operator promotes the replica by hand.

## 3. Capacity

3.1 Today's peak is 400 orders per second.
3.2 We expect ten times that peak within three years.
3.3 One larger server handles five times today's peak.

## 4. Retries

4.1 Clients retry a failed order up to 3 times.
4.2 Each retry waits 2 seconds.
4.3 Retries use the same order id, so a repeated order is ignored.

## 5. Access

5.1 Staff log in through the central login service.
5.2 A disabled staff account loses access at once.
5.3 Permissions are cached for one hour on each server.

## 6. Main promises

- No confirmed order is lost in a data-centre outage.
- A disabled user loses access at once.
- A repeated order is never charged twice.
