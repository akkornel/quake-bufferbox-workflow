#!/usr/bin/perl -w

use strict;
use warnings;

use Cwd;


# This is a support script, which is loaded by the various "bbox-workflow"
# programs.  It is not meant to be executed directly.
#
# This support script has miscellaneous code.
# 
# NOTE: This code relies heavily on dolog, which must be loaded into the same
# scope as this code, or else things will fail.

# This file is Copyright (C) 2016 The Board of Trustees of the Leland Stanford
# Jr. University.  All rights reserved.


# barcode_path: Given a runfolder, return the path to the laneBarcode.html file.
# $runfolder: The path to the runfolder to search.
# Returns a path, or undef if the file wasn't found.
sub barcode_path {
	my ($runfolder) = @_;

	# Start by appeding what we know about the path
	my $html_path = "$runfolder/Data/Intensities/BaseCalls/Reports/html";

	# Look in our html_path for a directory
	my $html_handle;
	my $html_dir;
	opendir($html_handle, $html_path) or do {
		dolog(<<"EOF");
We have just run into problems trying to find the laneBarcode.html file
The directory we tried to access is: $html_path
The error we got is: $!
EOF
		return undef;
	};
	while (my $candidate = readdir($html_handle)) {
		next unless -d "$html_path/$candidate";
		$html_dir = "$html_path/$candidate";
	}
	closedir($html_handle);

	# If we found our directory, then return the full path
	if (defined($html_dir)) {
		return "$html_dir/all/all/all/laneBarcode.html";
	} else {
		return undef;
	}
}


# validate_path: Make sure a path (a directory) is readable, executable, and is
# a directory.
# $path: The path to validate.
# Returns the absolute path, or undef if there was a problem.
sub validate_path {
	my ($path) = @_;

	if (   (-r $path)
	    && (-x $path)
	    && (-d $path)
	) {
		$path = Cwd::abs_path($path);
		return $path;
	} else {
		return undef;
	}
}


# directory_rename: Append .old to a directory.
# $path: The path to the directory to rename.
sub directory_rename {
	my ($path) = @_;
	my $new_name = "$path.old";
	if (-r $new_name) {
		directory_rename($new_name);
	}
	rename($path, $new_name);
}


# End on a true value.
1;
