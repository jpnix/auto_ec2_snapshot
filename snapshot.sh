#!/bin/bash
#
# Written by James Permenter, any questions jpermenter@phishlabs.com
#
# This script will take an instance ID from the first position argument and snapshot it using
# our format.  It will then look for other snapshots that is has previously made for this
# instance and delete them if they are older than $retention_days old. 
# Schedule one cron job each per instance.
# Privs granted through IAM roles.
#
# Error handling

export PATH=$PATH:/usr/local/bin/:/usr/bin
set -ue
set -o pipefail

# Set variables necessary for command line switches

usage="Usage: shapshot.sh -i <AWS EC2 instance ID> -r <number of days of old backups to retain> [-m <max size of volume to snapshot in GB>] [-l <region, defaults to us-east-1>]"
instance_id=
retention_days= 
max_volume_size="200"
region="us-east-1"

# Get command line switches

while getopts i:r:m:l: opt; do
  case $opt in
  i)
      instance_id=$OPTARG
      ;;
  r)
      retention_days=$OPTARG
      ;;
  m)
      max_volume_size=$OPTARG
      ;;
  l)
      region=$OPTARG
      ;;
  esac
done

# Evaluate mandatory command line switches

shift $((OPTIND - 1))

if [ -z "$instance_id" ]
	then
		echo "No instance ID specificed."
		echo $usage
		exit 0
fi

if [ -z "$retention_days" ]
        then
                echo "Number of days of old snapshots to keep not specified."
                echo $usage
                exit 0
fi

# Define variables

retention_date_in_seconds=$(date +%s --date "$retention_days days ago")
logfile_path="/var/log/ec2_snapshots/"
name_tag=$(/usr/bin/aws ec2 describe-instances --region $region --instance-ids $instance_id --query 'Reservations[].Instances[].Tags[?Key==`Name`].Value[]' --output text)
logfile_name="automated_snapshots_"$name_tag"_$(date +"%Y%m%d-%H:%M").log"
logfile="$logfile_path$logfile_name"
gz=".gz"
final_message="$(date): Snapshot created/cleanup of snapshots over $retention_days days old on $name_tag ($instance_id) in $region complete.  View $logfile$gz on $(hostname) for complete details."
snstopic="arn:aws:sns:us-east-1:411853217841:Amazon_SysAdmin_Alerts"
snsregion="us-east-1"
touchpath="/opt/phishlabs/touchfiles/backups/"

# Create logfile dir if not present

mkdir -p $logfile_path

echo "$(date): Writing logfile at: $logfile"

# Output selection for -m flag if that switch was present.

if [ -z "$max_volume_size" ]
        then
                echo "$(date): No maximum volume size specified with -m so using the default value of $max_volume_size GB." | tee -a $logfile
        else
                echo "$(date): Only snapshotting volumes $max_volume_size GB and smaller." | tee -a $logfile
fi

# Loop through all volumes attached to this host and snapshot them.

for volume_id in $(/usr/bin/aws ec2 describe-volumes --region $region --filters Name=attachment.instance-id,Values=$instance_id --query 'Volumes[*].{ID:VolumeId}' --output text)
	do
                volume_size=$(aws ec2 describe-volumes --region $region --query 'Volumes[*].{Size:Size}' --filters Name=volume-id,Values=$volume_id --output text)
		device_id=$(/usr/bin/aws ec2 describe-volumes --region $region --query 'Volumes[*].Attachments[*].{Device:Device}' --filters Name=volume-id,Values=$volume_id --output text)
		if [ $volume_size -gt $max_volume_size ]
			then
				echo "$(date): SKIPPED! - Snapshot of $volume_id mounted at $device_id on instance $instance_id with hostname $name_tag skipped because it is larger than $max_volume_size GB." | tee -a $logfile
			else
				description="WS - $name_tag $device_id - Automated Snapshot $instance_id - $(date +'%Y%m%d') - poc MGMT"
				snapshot_id="$(/usr/bin/aws ec2 create-snapshot --region $region --volume-id $volume_id --description "$description" --output text | awk '{for (i=1;i<=NF;i++) {if ($i ~/snap-/) {print $i}}}')"
				echo "$(date): Snapshot $snapshot_id of $volume_id mounted at $device_id on instance $instance_id with hostname $name_tag initiated in EC2." | tee -a $logfile
				/usr/bin/aws ec2 create-tags --region $region --resources $snapshot_id --tags Key=Name,Value="$description"
				/bin/touch $touchpath$name_tag
		fi
	done

# Cleanup of old snapshots this script has taken for this instance.

echo "$(date): Cleaning up automated snapshots over $retention_days days old." | tee -a $logfile

for snapshots_taken in $(/usr/bin/aws ec2 describe-snapshots --region $region --output text | grep "Automated Snapshot" | grep $instance_id | awk '{for (i=1;i<=NF;i++) {if ($i ~/snap-/) {print $i}}}')

			do
				snapshot_date=$(aws ec2 describe-snapshots --region $region --output=text --snapshot-ids $snapshots_taken --query Snapshots[].StartTime | awk -F "T" '{printf "%s\n", $1}')
				snapshot_date_in_seconds=$(date "--date=$snapshot_date" +%s)
				snapshot_description=$(aws ec2 describe-snapshots --snapshot-id $snapshots_taken --region $region --output text | grep -v ^TAGS)

					if (( $snapshot_date_in_seconds <= $retention_date_in_seconds )); then
						echo "$(date): DELETING snapshot $snapshots_taken. Description: $snapshot_description ..." | tee -a $logfile
						/usr/bin/aws ec2 delete-snapshot --region $region --snapshot-id $snapshots_taken
					else
						echo "$(date): Not deleting snapshot $snapshots_taken. Description: $snapshot_description ..." | tee -a $logfile
					fi
			done

# Send Final Message
/usr/bin/aws sns publish --region $snsregion --topic-arn $snstopic --message "$final_message" | tee -a "$logfile_path""$logfile_name"

# Clean Up old log files over 30 days old
/bin/find $logfile_path* -mtime +30 -exec rm {} \;

#Gzip Log file at completion
/bin/gzip -f "$logfile_path""$logfile_name"

exit

