#!/usr/bin/perl -w

use strict;
use warnings;

use Fcntl qw(:flock);


# This is a support script, which is loaded by the various "bbox-workflow"
# programs.  It is not meant to be executed directly.
#
# This support script has all of the lockfile and logging code.

# This file is Copyright (C) 2016 The Board of Trustees of the Leland Stanford
# Jr. University.  All rights reserved.


# log_open: Open our log file, naming any file in place.
# $log_path: The path to the log file, which might exist.
# $log_ref: A reference to a scalar, whose content is written to the log.
# Returns an open file handle, or false.
sub log_open {
	my ($log_path, $log_ref) = @_;
	my $log_handle;

	# If our log file exists, then rename it by appending ".old".
	if (-r $log_path) {
		log_rename($log_path);
	}

	# Try opening our log file, and set autoflush.
	# autoflush, in particular, is important: If we don't do that, and we
	# have to send the log file somewhere, it might not all be written to
	# disk.
	open($log_handle, '>', $log_path) or do {
		dolog(<<"EOL");
We are having trouble opening the log file.
The file we tried to create is: $log_path
The error we got is: $!
EOL
		return 0;
	};
	my $old_handle = select($log_handle);
	$| = 1;
	select($old_handle);

	# Put a header into the log file.
	# Also, if we have anything in our holding variable, output it.
	my $start_time = localtime(time());
	print $log_handle <<"EOL";
This is the log of the bbox-workflow program!
This log file was started on: $start_time
If you need help, please email research-computing-support\@stanford.edu
EOL
	if (defined($log_ref)) {
		print $log_handle ${$log_ref};
		${$log_ref} = '';
	}

	# The log is ready to go!
	return $log_handle;
}

# log_rename: Rename a log file, by appending .old
# We make this a separate subroutine because we might recurse.
# $file: The file to rename.
sub log_rename {
	my ($file) = @_;
	if (-r "$file.old") {
		log_rename("$file.old");
	}
	rename($file, "$file.old");
	return 1;
}

# log_close: Close the log.
# $log_handle: An open file handle.
sub log_close {
	my ($log_handle) = @_;
	return unless defined($log_handle);
	my $end_time = localtime(time());
	print $log_handle <<"EOL";
The time is now $end_time.
Logging complete!
EOL
	close($log_handle);
	return 1;
}
	
# log_msg: Log stuff.
# $log_handle: A file handle, or undef.
# $log_ref: A scalar reference, to write the log file if $log_handle is undef.
# $message: The message to log.
sub log_msg {
	my ($log_handle, $log_ref, $message) = @_;

	# First, print the log entry to standard output
	print $message;

	# Next, if the log file is open, output it there.
	# If the log file isn't open, then write to our holding variable.
	if (defined($log_handle)) {
		print $log_handle $message;
	} else {
		${$log_ref} .= $message;
	}
}

# lock_get: Create and lock our lock file.
# $lock_path: The path to the lock file.
# $log_path: The path to where the log should be.
# Returns a file handle, or false.
sub lock_get {
	my ($lock_path, $log_path) = @_;
	my $lock_handle;

	# First, open the lock file, in append mode.
	# We open in append mode because we don't want to change anything
	# immediately.  We'll wait for the lock first.
	open ($lock_handle, '>>', $lock_path) or do {
		dolog(<<"EOL");
We have just tried to create/open the following file:
$lock_path
However, we got this error: $!
This should not happen.  Please contact Support!
EOL
		return 0;
	};

	# Actually take the lock.  If already locked, fail immediately.
	flock($lock_handle, LOCK_EX | LOCK_NB) or do {
		dolog(<<"EOL");
It appears that the run folder you specified is already being actively worked
on by another instance of the workflow program.  You should wait for that other
instance to complete.  To see what it's doing, you can look at the log file,
which should be here: $log_path
EOL
		return 0;
	};

	# We are locked!  Turn on autoflush, write our process ID, and return.
	my $old_handle = select($lock_handle);
	$| = 1;
	select($old_handle);
	truncate($lock_handle, 0);
	print $lock_handle "$$\n";
	dolog("Lock file $lock_path locked.\n");
	return 1;
}

# lock_release: Release our lock.
# $lock_path: The path to the lock file.
# $lock_handle: A file handle, or undef.
sub lock_release {
	my ($lock_path, $lock_handle) = @_;
	return unless defined($lock_handle);
	unlink($lock_path);
	flock($lock_handle, LOCK_UN);
	close($lock_handle);
	return 1;
}


# End on a true value.
1;
