# Automated snapshots for EC2 Instances.

## About

 This script will take an instance ID from the first position argument and snapshot it using
 our format.  It will then look for other snapshots that is has previously made for this
 instance and delete them if they are older than $retention_days old. 
 Schedule one cron job each per instance.
 Privs granted through IAM roles.

## Usage

```
shapshot.sh -i <AWS EC2 instance ID> -r <number of days of old backups to retain> [-m <max size of volume to snapshot in GB>] [-l <region, defaults to us-east-1>]
```

## Cron

```
# Backup preprocess daily @ 9:23 Z and delete backups > 45 days old
24  09 * * * /opt/phishlabs/scripts/snapshot.sh -i i-0ae72060be407724e -r 14 >/dev/null 2>&1
```
##

```
★ ❀ ヅ ❤ ♫
```
