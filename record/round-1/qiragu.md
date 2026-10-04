# Review by @qiragu

- all checks passed

## Opened text

```
arch-panel-review: v1
review: spike-s2
round: 1
author: qiragu
bot: none
position: disagree
reason: One Postgres server with a 5-minute replica loses up to 5 minutes of confirmed orders in an outage, which breaks the first main promise.
looked-at: section 2 (storage), section 4 (retries), section 6 (main promises)
comment: line=9 kind=blocker text=A replica updated every 5 minutes loses up to 5 minutes of confirmed orders when data centre A fails. That breaks "No confirmed order is lost".
comment: line=10 kind=risk text=Promotion by hand depends on an operator being awake. How long does it take at 3 am? Proposed check: a timed failover drill.
comment: line=25 kind=advice text=Name the retry limit in one place so clients and servers can't drift apart.
```
