#!/bin/bash

pass="phrase"
today="$(date +\%Y-\%m-\%d)"

remote_server=user@address
path_to_dir='/path_to_dir'
tar_dir=$today-_dir.tar.gz

remote_server_space_used=`ssh $remote_server df -H |grep "/dev/root_drive" |awk '{print $3}' | sed 's/.$//'`
[ $remote_server_space_used -gt 500 ] && echo "The backup failed due to a lack of additional space on the target." | sendmail -F site.local -t john.doe@gmail.com || echo "Running the backup script..."
[ $remote_server_space_used -gt 500 ] && exit || echo ""
[ -d "${path_to_dir}" ] &&  echo "Source directory $path_to_dir found." || echo "Source directory not attached. Stopping the backup script." | sendmail -F site.local -t john.doe@gmail.com
[ -d "${path_to_dir}" ] && echo "" || exit

cd $path_to_dir

###########################################################
# Backups less than 10GB ##################################
###########################################################
backup_size=`du -s -B1 $path_to_dir/_dir | awk -F'/' '{print $1}'`
backup_single_tarball(){
	echo "backup_single_tarball()"
	tar cvf $tar_dir _dir/
	[ $? -eq 0 ] && echo "<10GB Tar Passed"; backup_single_encrypt || echo "<10GB Tar Failed"
}
backup_single_encrypt(){
	echo "backup_single_encrypt()"
	gpg -c --batch --passphrase "$pass" $tar_dir
	[ $? -eq 0 ] && echo "<10GB GPG Passed" || echo "<10GB GPG Failed"
	GPG_PID=`ps aux |grep "gpg -c --batch --passphrase" |awk '{print $2}' |head -1 |grep -v grep`
	until [ "$GPG_PID" == "" ]; do
		echo "GPG PID: $GPG_PID"
		echo "GPG has finished encrypting the $tar_dir tarball."
		sleep 60;
		backup_single_send
		exit;
	done
}
backup_single_send(){
	echo "backup_single_send()"
	rm $path_to_dir/$tar_dir
	[ $? -eq 0 ] && echo "<10GB Removed tarball." || echo "<10GB Failed to remove tarball."
	/bin/rsync -e "ssh -o StrictHostKeyChecking=no" --rsync-path="rsync" --bwlimit=5000 $path_to_dir/$tar_dir.gpg $remote_server:~/encrypted/_dir/
	[ $? -eq 0 ] && echo "<10GB rsync passed." || echo "<10GB rsync failed."
	trap "rm $path_to_dir/$tar_dir.gpg" EXIT
	[ $? -eq 0 ] && echo "<10GB Removed GPG." || echo "<10GB Failed to remove GPG."
}
###########################################################
# Backups greater than 10GB ###############################
###########################################################
backup_multiple_tarball(){
	echo "backup_multiple_tarball()"
	tar cvzf - $path_to_dir/_dir | split -b 10000m - $tar_dir.
	[ $? -eq 0 ] && echo "Created multi tarball."; backup_multiple_encrypt || echo "Failed to create multi tarball."
}
backup_multiple_encrypt(){
	for file in $(ls | grep ".gz"); do gpg -c --batch --passphrase $pass $file && rm -f $file; done
	[ $? -eq 0 ] && echo "GPG Passed & removed multi tarball" || echo "GPG failed & couldn't remove multi tarball"
	GPG_PID=`ps aux |grep "gpg -c --batch --passphrase" |awk '{print $2}' |head -1 |grep -v grep`
	until [ "$GPG_PID" == "" ]; do
		echo "GPG PID: $GPG_PID"
		echo "GPG has finished encrypting the $tar_dir tarball."
		sleep 60;
		backup_multiple_send
		exit;
	done
}
backup_multiple_send(){
	/bin/rsync -e "ssh -o StrictHostKeyChecking=no" --rsync-path="rsync" --bwlimit=5000 $path_to_dir/*.gpg $remote_server:~/encrypted/_dir/
	[ $? -eq 0 ] && echo "Multi file rsync passed." || echo "Multi file rsync failed."
	trap "rm $path_to_dir/*.gpg" EXIT
	[ $? -eq 0 ] && echo "Removed multi GPG." || echo "Failed to remove multi GPG."
}
[ $backup_size -gt 10000000000 ] && backup_multiple_tarball || backup_single_tarball

sleep 60;

trap "echo 'Backup script finished.' | sendmail -F site.local -t john.doe@gmail.com" EXIT
