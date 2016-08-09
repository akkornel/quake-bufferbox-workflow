#!/usr/bin/perl -w

use strict;
use warnings;

use Email::MIME;
use Email::Send;
use Sys::Hostname;


# This is a support script, which is loaded by the various "bbox-workflow"
# programs.  It is not meant to be executed directly.
#
# This support script has all of the email-related code.
#
# NOTE: This code relies heavily on log_* subroutines.  Those subroutines must
# be loaded into the same scope as this code, or else things will fail.


# check_email: Check (and create) the email configuration file.
# $path: The path to the configuration file.
sub check_email {
	my ($path) = @_;

	# Only create if the file doesn't exist
	if (! -r $path) {
		log_msg("Missing $path.  Creating now.\n");
		my $email_handle;
		open($email_handle, '>', $path) or do {
			log_msg(<<"EOF");
We are having problems creating one of our configuration files.
The file we are trying to create is: $path
The error we are getting is: $!
EOF
			return 0;
		};

		print $email_handle <<EOF;
# This file contains the list of email addresses what should be notified
# whenever something happens.  "something" includes things like...
# * A run completing, but something being wrong with the sample sheet.
# * A run completing, and being analyzed successfully.
# * A run folder appearing, but never completing.
#
# The format of this file is simple:
# * Empty lines are ignored.
# * Lines which start with a hash (like this one) are ignored.
# * Other lines are treated as email addresses.
# To add email addresses, simply add the email address on a new line.
#
# NOTE: This file is read right before bbox-workflow tries to send an email.

nobody\@stanford.edu
EOF

		close($email_handle);
	}

	return 1;
}


# email_recipients: Parse our email config file to get a list of recipients.
# $path: The path to the email configuration file.
sub email_recipients {
	my ($path) = @_;

	my $email_handle;
	open($email_handle, '<', $path) or do {

	};

	# Go through each line, building our address list
	my @list;
	while (my $line = <$email_handle>) {
		# Remove any line endings.  We need to do this specially in case
		# the file was modified on Windows.
		$line =~ s{\A(\S+)[\r\n]*\z}{$1}xims;

		# Skip blank lines and comments
		next if $line =~ m{\A\s+\z}xims;
		next if $line =~ m{\A\#}xims;

		# Read each line as an email address
		push @list, $line;
	}

	# Return a comma-separated string
	return join(',', @list);
}


# email_analysis: Send an email when the analysis is complete.
# $runfolder: The path to the run folder.
# $config: Our email recipients config file.
# $log_path: The path to the log file.
# $bin_path: The path to the script directory.
# $script_name: The name of the script being run.
sub email_analysis {
	my ($runfolder, $config, $log_path, $bin_path, $script_name) = @_;

	# Create the body part
	my $email_body = Email::MIME->create(
		attributes => {
			content_type => 'text/plain',
			charset      => 'UTF-8',
			encoding     => 'quoted-printable',
		}
	);
	my $email_body_text = "Hello!\n\nThis is $script_name, running on ";
	$email_body_text .= hostname() . '.  ';
	$email_body_text .= <<"EOF";
An analysis has just been completed, using the data in the following run folder:

$runfolder

The log from the run is being attached as "workflow-log.txt", along with
"laneBarcodes.html".

If everything looks good, you can deliver the files to the client by running
the following command:

sudo $bin_path/$script_name deliver $runfolder

(You can just copy/paste the above line into a PuTTY or SecureCRT session.)

If you still need assistance, please forward this mail (with attachments) to research-computing-support\@stanford.edu.

Have a good day!

~ Mr. Workflow
EOF
	$email_body->body_str_set($email_body_text);

	# Create the log file attachment
	my $email_log = Email::MIME->create(
		attributes => {
			disposition  => 'attachment',
			name         => 'workflow-log.txt',
			content_type => 'text/plain',
			charset      => 'iso-8859-1',
			encoding     => 'base64',
		},
	);

	# We should have a log file, so read it into memory
	my $log_handle;
	my $log_body = '';
	open($log_handle, '<', $log_path) or do {
		log_msg(<<"EOF");
We have just encounted a problem when trying to re-open our log file.
The file we were trying to read is: $log_path
The error we got is: $!
EOF
		return 0;
	};
	while (my $line = <$log_handle>) {
		$log_body .= $line . "\n";
	}
	$email_log->body_set($log_body);
	close ($log_handle);
	undef $log_body;

	# Create the laneBarcode attachment
	my $email_barcode = Email::MIME->create(
		attributes => {
			disposition  => 'attachment',
			name         => 'laneBarcode.html',
			content_type => 'text/html',
			charset      => 'iso-8859-1',
			encoding     => 'base64',
		},
	);

	# Get the laneBarcode HTML file, and read it into memory
	my $barcode_path = barcode_path($runfolder);
	return 0 unless defined($barcode_path);
	my $barcode_handle;
	my $barcode_body = '';
	open($barcode_handle, '<', $barcode_path) or do {
		log_msg(<<"EOF");
We have just encountered a roblem when trying to open the landBarcode HTML file.
The file we were trying to read is: $barcode_path
The error we got is: $!
EOF
		return 0;
	};
	while (my $line = <$barcode_handle>) {
		$barcode_body .= $line . "\n";
	}
	$email_barcode->body_set($barcode_body);
	close($barcode_handle);
	undef $barcode_body;

	# Create the email
	my $email_subject = "Completed analysis by $script_name on " .
	                    hostname();
	my $email = Email::MIME->create(
		header_str => [
			From    => 'noreply@stanford.edu',
			To      => email_recipients($config),
			Subject => $email_subject,
		],
		parts      => [ $email_body, $email_log, $email_barcode ],
	);
	log_msg('Sending a ' . length($email->as_string) . '-byte email to ');
	log_msg(email_recipients($config) . "\n");

	# Send the email
	my $email_sender = Email::Send->new({
		mailer      => 'SMTP',
		mailer_args => [
			Host => 'smtp-unencrypted.stanford.edu',
		],
	});
	my $send_result = $email_sender->send($email->as_string);
	if (!$send_result) {
		log_msg("Error sending email: $send_result\n");
		return 0;
	}

	# Finally, done!
	return 1;
}

# email_failure: Send an email when something goes wrong.
# $message: A message explaining what happened.
# $action: The action being performed.
# $runfolder: The path to the run folder.
# $config: Our email recipients config file.
# $log_path: The path to the log file, or undef (if there is no log file).
# $log_ref: A scalar ref, pointing to and unwritten log content.
# $bin_path: The path to the script directory.
# $script_name: The name of the script being run.
sub email_failure {
	my ($message, $action, $runfolder, $config, $log_path, $log_ref, $bin_path, $script_name) = @_;

	# Create the body part
	my $email_body = Email::MIME->create(
		attributes => {
			content_type => 'text/plain',
			charset      => 'UTF-8',
			encoding     => 'quoted-printable',
		}
	);
	my $email_body_text = "Hello!\n\nThis is $script_name, running on ";
	$email_body_text .= hostname() . '.  ';
	$email_body_text .= <<"EOF";
I am emailing you to report that something went wrong.

Here's a couple-word summary of what's going on:

> $message

If a log is available, it is being attached as "workflow-log.txt".

When you have a moment, please investigate.  To re-run the workflow, use the following command:

$bin_path/$script_name $action $runfolder

(You can just copy/paste the above line into a PuTTY or SecureCRT session.)

If you still need assistance, please forward this mail (with attachments) to research-computing-support\@stanford.edu.

Apologies for the inconvenience!

~ Mr. Workflow
EOF
	$email_body->body_str_set($email_body_text);

	# Create the log file attachment
	my $email_file = Email::MIME->create(
		attributes => {
			disposition  => 'attachment',
			name         => 'workflow-log.txt',
			content_type => 'text/plain',
			charset      => 'iso-8859-1',
			encoding     => 'base64',
		},
	);

	# If we have a log file, then re-read it into memory
	if (defined($log_path)) {
		my $log_handle;
		my $log_body = '';
		open($log_handle, '<', $log_path) or do {
			log_msg(<<"EOF");
We have just encounted a problem when trying to re-open our log file.
This happened while trying to report an error.
The file we were trying to read is: $log_path
The error we got is: $!
EOF
			return 0;
		};
		while (my $line = <$log_handle>) {
			$log_body .= $line . "\n";
		}
		$email_file->body_set($log_body);
	} else {
		# If there's no log file, then use what's in memory already.
		$email_file->body_str_set($$log_ref);
	}

	# Create the email
	my $email_subject = "Something went wrong with $script_name on " .
	                    hostname();
	my $email = Email::MIME->create(
		header_str => [
			From    => 'noreply@stanford.edu',
			To      => email_recipients($config),
			Subject => $email_subject,
		],
		parts      => [ $email_body, $email_file ],
	);
	log_msg('Sending a ' . length($email->as_string) . '-byte email to ');
	log_msg(email_recipients($config) . "\n");

	# Send the email
	my $email_sender = Email::Send->new({
		mailer      => 'SMTP',
		mailer_args => [
			Host => 'smtp-unencrypted.stanford.edu',
		],
	});
	my $send_result = $email_sender->send($email->as_string);
	if (!$send_result) {
		log_msg("Error sending email: $send_result\n");
		return 0;
	}

	# Finally, done!
	return 1;
}


# email_delivery_manual: Send an email when manual delivery is necessary
# $project: The path to the Project directory.
# $config: Our email recipients config file.
# $script_name: The name of the script being run.
sub email_delivery_manual {
	my ($project, $config, $script_name) = @_;

	# Create the body part
	my $email_body = Email::MIME->create(
		attributes => {
			content_type => 'text/plain',
			charset      => 'UTF-8',
			encoding     => 'quoted-printable',
		}
	);
	my $email_body_text = "Hello!\n\nThis is $script_name, running on ";
	$email_body_text .= hostname() . '.  ';
	$email_body_text .= <<"EOF";
I am emailing you to report that I tried to deliver Project results to someone, but it appears the associated username does not have a local account.

The Project directory can be found here:

$project

Please contact the user and arrange to deliver the results to them.

Apologies for the inconvenience!

~ Mr. Workflow
EOF
	$email_body->body_str_set($email_body_text);

	# Create the email
	my $email_subject = 'Project results ready for manual delivery (from ' .
	                    "$script_name on " . hostname() . ')';
	my $email = Email::MIME->create(
		header_str => [
			From    => 'noreply@stanford.edu',
			To      => email_recipients($config),
			Subject => $email_subject,
		],
		parts      => [ $email_body ],
	);
	log_msg('Sending a ' . length($email->as_string) . '-byte email to ');
	log_msg(email_recipients($config) . "\n");

	# Send the email
	my $email_sender = Email::Send->new({
		mailer      => 'SMTP',
		mailer_args => [
			Host => 'smtp-unencrypted.stanford.edu',
		],
	});
	my $send_result = $email_sender->send($email->as_string);
	if (!$send_result) {
		log_msg("Error sending email: $send_result\n");
		return 0;
	}

	# Finally, done!
	return 1;
}

# email_delivery_complete: Send an email when automatic delivery completed
# $project: The path to the Project directory.
# $destination: The place where everything was copied.
# $config: Our email recipients config file.
# $script_name: The name of the script being run.
sub email_delivery_complete {
	my ($project, $destination, $config, $script_name) = @_;

	# Create the body part
	my $email_body = Email::MIME->create(
		attributes => {
			content_type => 'text/plain',
			charset      => 'UTF-8',
			encoding     => 'quoted-printable',
		}
	);
	my $email_body_text = "Hello!\n\nThis is $script_name, running on ";
	$email_body_text .= hostname() . '.  ';
	$email_body_text .= <<"EOF";
I am emailing you to report that I have successfully delivered Project results!

I copied files from the following Project directory:

$project

The files have been copied to the following location:

$destination

Please pull whatever other reports are needed, and let the user know that his/her files are ready.

Have a great day.  Go Tree!

~ Mr. Workflow
EOF
	$email_body->body_str_set($email_body_text);

	# Create the email
	my $email_subject = 'Project results delivered! (from ' .
	                    "$script_name on " . hostname() . ')';
	my $email = Email::MIME->create(
		header_str => [
			From    => 'noreply@stanford.edu',
			To      => email_recipients($config),
			Subject => $email_subject,
		],
		parts      => [ $email_body ],
	);
	log_msg('Sending a ' . length($email->as_string) . '-byte email to ');
	log_msg(email_recipients($config) . "\n");

	# Send the email
	my $email_sender = Email::Send->new({
		mailer      => 'SMTP',
		mailer_args => [
			Host => 'smtp-unencrypted.stanford.edu',
		],
	});
	my $send_result = $email_sender->send($email->as_string);
	if (!$send_result) {
		log_msg("Error sending email: $send_result\n");
		return 0;
	}

	# Finally, done!
	return 1;
}


# email_delivery_problem: Send an email when the delivery didn't work.
# $runfolder: The path to the run folder.
# $project: The path to the Project_ directory.
# $destination: The place where we tried to do the copy.
# $config: Our email recipients config file.
# $log_path: The path to the log file, or undef (if there is no log file).
# $bin_path: The path to the script directory.
# $script_name: The name of the script being run.
sub email_delivery_problem {
	my ($runfolder, $project, $destination, $config, $log_path, $bin_path, $script_name) = @_;

	# Create the body part
	my $email_body = Email::MIME->create(
		attributes => {
			content_type => 'text/plain',
			charset      => 'UTF-8',
			encoding     => 'quoted-printable',
		}
	);
	my $email_body_text = "Hello!\n\nThis is $script_name, running on ";
	$email_body_text .= hostname() . '.  ';
	$email_body_text .= <<"EOF";
I am emailing you to report that something went wrong.

We were attempting to do a delivery, but that delivery failed.

We tried copying the following Project_ directory:

$project

We tried copying to the following location:

$destination

If a log is available, it is being attached as "workflow-log.txt".

When you have a moment, please investigate.  To re-run the delivery, use the following command:

sudo $bin_path/$script_name deliver $runfolder

(You can just copy/paste the above line into a PuTTY or SecureCRT session.)

If you still need assistance, please forward this mail (with attachments) to research-computing-support\@stanford.edu.

Apologies for the inconvenience!

~ Mr. Workflow
EOF
	$email_body->body_str_set($email_body_text);

	# Create the log file attachment
	my $email_file = Email::MIME->create(
		attributes => {
			disposition  => 'attachment',
			name         => 'workflow-log.txt',
			content_type => 'text/plain',
			charset      => 'iso-8859-1',
			encoding     => 'base64',
		},
	);

	# If we have a log file, then re-read it into memory
	if (defined($log_path)) {
		my $log_handle;
		my $log_body = '';
		open($log_handle, '<', $log_path) or do {
			log_msg(<<"EOF");
We have just encounted a problem when trying to re-open our log file.
This happened while trying to report an error.
The file we were trying to read is: $log_path
The error we got is: $!
EOF
			return 0;
		};
		while (my $line = <$log_handle>) {
			$log_body .= $line . "\n";
		}
		$email_file->body_set($log_body);
	}

	# Create the email
	my $email_subject = "Something went wrong with $script_name on " .
	                    hostname();
	my $email = Email::MIME->create(
		header_str => [
			From    => 'noreply@stanford.edu',
			To      => email_recipients($config),
			Subject => $email_subject,
		],
		parts      => [ $email_body, $email_file ],
	);
	log_msg('Sending a ' . length($email->as_string) . '-byte email to ');
	log_msg(email_recipients($config) . "\n");

	# Send the email
	my $email_sender = Email::Send->new({
		mailer      => 'SMTP',
		mailer_args => [
			Host => 'smtp-unencrypted.stanford.edu',
		],
	});
	my $send_result = $email_sender->send($email->as_string);
	if (!$send_result) {
		log_msg("Error sending email: $send_result\n");
		return 0;
	}

	# Finally, done!
	return 1;
}


# End on a true value.
1;
