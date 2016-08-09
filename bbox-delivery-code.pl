#!/usr/bin/perl -w

use strict;
use warnings;

use File::Copy;


# This is a support script, which is loaded by the various "bbox-workflow"
# programs.  It is not meant to be executed directly.
#
# This support script has all of the code that delivers files to end users.
#
# NOTE: This code relies heavily on log_* subroutines.  Those subroutines must
# be loaded into the same scope as this code, or else things will fail.


# deliver: Deliver files for a given project
# $runfolder The path to the run folder.
# $project: The name of the Project path.
# $email: The email-recipients.txt config file.
# $log: The path to the log file
# $bin_path: The path to the script directory.
# $script_name: The name of the script being run.
sub deliver {
	my ($runfolder, $project, $email, $log, $bin_path, $script_name) = @_;
	log_msg("Starting delivery for $project\n");

	# Extract the username
	$project =~ m{\AProject_(.+)\z}xims;
	my $project_path = "$runfolder/Data/Intensities/BaseCalls";
	my $username = $1;

	# Search for any home directories matching this username
	# We have a hard-coded exceptin for user "spyros"
	my @homedirs;
	if ($username eq 'spyros') {
		@homedirs = ('/b7_1/home/spyros');
	} else {
		@homedirs = glob "/b?_?/home*/$username";
	}

	# If we don't find anything, send an email and return
	if (!scalar(@homedirs)) {
		log_msg("No home directory found for $username!\n");
		email_delivery_manual("$project_path/$project", $email,
			              $script_name);
		return 1;
	}
	my $homedir = shift @homedirs;

	# Now, let's get to work
	# Start by getting the user's UID and GID.
	log_msg("Will do delivery to user $username\n");
	my @homedir_stat = stat($homedir);
	my $homedir_mode = $homedir_stat[2] & 07777;
	my $homedir_uid = $homedir_stat[4];
	my $homedir_gid = $homedir_stat[5];

	# Figure out what to call the folder name
	# We prefer to use the runfolder name, but if that exists already, then
	# fall back to some suffix like .0, .1, etc.
	my $runfolder_name = $runfolder;
	$runfolder_name =~ s{\A.+/(.+)\z}{$1}xims;
	my $i = -1;
	my $runfolder_suffix = '';
	while (-r "$homedir/$runfolder_name$runfolder_suffix") {
		if ($runfolder_suffix eq '') {
			$runfolder_suffix = '.0';
		} else {
			$i++;
			$runfolder_suffix = ".$i";
		}
	}
	my $destination = "$homedir/$runfolder_name$runfolder_suffix";
	log_msg("Will deliver files to $destination ");
	log_msg(sprintf("(mode %o)\n", $homedir_mode));

	# Create the directory to hold everything
	mkdir($destination, $homedir_mode);
	chown($homedir_uid, $homedir_gid, $destination);

	# Now let's begin to deliver everything
	# If delivery had a problem, send an email.
	deliver_directory("$project_path/$project", $destination,
	                  $homedir_uid, $homedir_gid) or do {
		email_delivery_problem($runfolder,
		                       "$project_path/$project", $destination,
		                       $email, $log, $bin_path, $script_name);
		return 1;
	};

	# Since delivery worked, send an email!
	email_delivery_complete("$project_path/$project", $destination, $email,
	                        $script_name);

	# All done!
	return 1;
}


# deliver_directory: Copy a directory to the destination, and chown
# $source: The path to the directory whose contents will be copied.
# $destination: The destination directory (which must already exist).
# $uid: The destination UID.
# $gid: The destination GID.
sub deliver_directory {
	my ($source, $destination, $uid, $gid) = @_;

	# Start listing the source directory contents
	my $source_handle;
	opendir($source_handle, $source) or do {
		log_msg(<<"EOF");
We were unable to read the source directory for our copy.
The directory we tried to read is: $source
The error we got is: $!
EOF
		return 0;
	};

	# Copy everything we find (but not . or ..)
	while (my $item = readdir($source_handle)) {
		next if $item eq '.';
		next if $item eq '..';

		# Work out the file/directory target and mode
		my $target = "$destination/$item";
		my $mode = (stat("$source/$item"))[2] & 07777;
		log_msg("$source/$item -> $target, ");
		log_msg(sprintf("mode %o\n", $mode));

		# Files are easy enough to copy
		if (-f "$source/$item") {
			File::Copy::copy("$source/$item", $target) or do {
				log_msg(<<"EOF");
We were unable to copy $item to its destination, because of an error.
The file we tried to copy is: $source/$item
The destination was: $target
The error is: $!
EOF
				return 0;
			};
			chmod($mode, $target);
			chown($uid, $gid, $target);
		}

		# For directories, we make the directory and then recurse
		elsif (-d "$source/$item") {
			mkdir($target, $mode);
			chown($uid, $gid, $target);
			my $res = deliver_directory("$source/$item", $target,
			                            $uid, $gid);
			return $res unless $res == 1;
		}

		# Skip other stuff
		else {
			log_msg("Skipping $source/$item, which is neither a ");
			log_msg("file nor a directory.\n");
		}
	}

	# All done with this directory!
	closedir($source_handle);
	return 1;
}


# End on a true value.
1;
