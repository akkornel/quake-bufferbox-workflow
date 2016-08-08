This document explains how to have the workflow programs run automatically.

To edit your crontab, run the command `crontab -e`.  That will open a text editor.  Inside the text editor, write the following three lines:

MAILTO=nobody@stanford.edu
*/15 * * * * /home/bufferbox/bbox-workflow/bbox-workflow-miseq scan /home/bufferbox/MiSeq >> /dev/null
*/15 * * * * /home/bufferbox/bbox-workflow/bbox-workflow-nextseq scan /home/bufferbox/NextSeq >> /dev/null

The first line says, "If there is any output generated, send it to "nobody@stanford.edu", which essentially means "discard it".

The second line says, "Every 15 minutes, run the bbox-workflow-miseq scan command, have it scan the MiSeq directory, and discard any output."  We say "discard any output" because if there is a problem, we should be emailed automatically!

The third line is basically the same as the second line, but for NextSeq.

As soon as the crontab is saved, it will take effect.  That means the scans should begin within 15 minutes.

To stop scans from running automatically, run the `crontab -e` command again, and delete some or all of the above lines.  For example, to stop the MiSeq scan, delete the line which mentions "MiSeq".

If you have any questions, don't hesitate to contact research-computing-support@stanford.edu.

Good luck!
