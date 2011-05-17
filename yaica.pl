#!/usr/bin/perl

############################################################################
#    Y A I C A                                                             #
#    Yet Another Image Converter for Attachments                           #
#    v0.1.1                                                                #
#                                                                          #
#    Copyright (C) 2006 by Boyan Tabakov                                   #
#    blade.alslayer@gmail.com                                              #
#                                                                          #
#    This program is free software; you can redistribute it and/or modify  #
#    it under the terms of the GNU General Public License as published by  #
#    the Free Software Foundation; either version 2 of the License, or     #
#    (at your option) any later version.                                   #
#                                                                          #
#    This program is distributed in the hope that it will be useful,       #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of        #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
#    GNU General Public License for more details.                          #
#                                                                          #
#    You should have received a copy of the GNU General Public License     #
#    along with this program; if not, write to the                         #
#    Free Software Foundation, Inc.,                                       #
#    59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             #
############################################################################

############################################################################
#NOTE to all Bulgarian speaking users:                                     #
#==========================================================================#
#                                                                          #
#Regardless of the name of the product it is absolutely                    #
#inappropriate to attempt any BOILING, FRYING, BACKING,                    #
#or any other transformations that aim to result in a                      #
#tasty MEAL! Furthermore, the product IS CERTAINLY NOT                     #
#INFECTED WITH BIRD FLU! Just in case you were wondering...                #
#                                                                          #
############################################################################

use 5.6.0;
use strict;
use warnings;

use Email::MIME;
use Image::Magick;

sub usage();					# Prints the usage of the programme.
sub get_args();				# Processes the command line arguments.
sub read_cfg();				# Read configuration file.
sub verify_cfg();			# Validates the values of all parameters.
sub read_message();		# Read email message from standard input.
sub get_images($$);		# ($msg, \@arr) loop through $msg (Email::MIME) and build list of parts, containing images, in @arr.
sub store_image($$);	# ($img, $fname) save the image pointed by $img (Email::MIME) with filename $fname and propper extension for the format.
sub form_prefix($);		# ($msg) form filename prefix from the headers of $msg (Email::MIME). Prefix is '<sender email>-<id>'.
sub yaica_error($);   # Print error message and die painfully...

sub main();

our $version = "0.1.1";

# default config
our $cfg_file;
		$^O eq 'MSWin32' and
		$cfg_file = 'c:\Program Files\Yaica\yaica.conf' or
		$cfg_file = '/usr/local/etc/yaica.conf';
our %cfg = (
	'tiff_fax'=>0,
	'dest_format'=>'jpeg',
	'dest_dir'=>'.',
	'jpeg_quality'=>80,
	'ignore_convert'=>0,
	'grayscale'=>0,
	'copy'=>0,
	'input_file'=>undef,
	);
our %args = (
	'c'=>\$cfg{'copy'},
	'i'=>\$cfg{'ignore_convert'},
	'g'=>\$cfg{'grayscale'},
	'x'=>\$cfg{'tiff_fax'},
	'f'=>\$cfg{'dest_format'},
	'd'=>\$cfg{'dest_dir'},
	'q'=>\$cfg{'jpeg_quality'},
	'r'=>\$cfg{'input_file'}
	);
our %yesno = ('yes', 1, 'no', 0);	# just a helper
our $message_id = '<init>';

sub usage(){
	print "Yet Another Image Converter for Attachments v$version\n",
	"Expects e-mail message on stdin (see -r).\n",
	"Usage: yaica [options]\n",
	"  -r [filename]  - Read from specified file instead of standard input\n",
	"  -f [jpeg|tiff] - Set destination image format.\n",
	"  -d [dirname]   - Set destination directory.\n",
	"  -q [n]         - Set jpeg quality - 'n' must be [1, 100].\n",
	"  -g             - Convert to grayscale image.\n",
	"  -x             - Output tiff for faxing. Destination format must be 'tiff', ignores -g.\n",
	"  -i             - Ignore all convertions if image is in correct format.\n",
	"                   Note that this will result in EXACT duplicate\n",
	"                   of the attached image and options -q, -g and -x are ignored.\n",
	"                   This will speed up processing.\n",
	"  -c             - Creates exact duplicate of the original image, regardless of\n",
	"                   the source and destination formats. Ignores all other options except for -d.\n",
	"                   This will speed up processing.\n",
	"The flags g, x, i and c may be used with '+' to turn off the given option (e.g. yaica -g +c).\n",
	"This is useful when you have the option set to 'yes' in the config file.\n";
	exit 1;
	# Help!... heeeelp!...
	# Yes - that's right! yaica -h returns error code! You are not allowed to ask for help...
}

sub yaica_error($){
	my $msg = shift;
	$msg = $message_id."\nYaica Error: ".$msg;
	die $msg;
}

sub get_args(){
	# Seems ok, but who knows?
	while (@ARGV){
		my $val;
		$_ = shift @ARGV;
		SWITCH:{
			/^-([fdqr])$/ && do{
				$val = shift @ARGV;
				${$args{$1}} = $val;
				last SWITCH;
			};
			/^-([xigc]+)$/ && do{
				my @opts = split //, $1;
				foreach my $opt (@opts){
					${$args{$opt}} = 1;
				}
				last SWITCH;
			};
			/^\+([xigc]+)$/ && do{
				my @opts = split //, $1;
				foreach my $opt (@opts){
					${$args{$opt}} = 0;
				}
				last SWITCH;
			};
			/.*/ && usage();
		};
	}
}

sub read_cfg(){
	open (CONF, "<", $cfg_file) or yaica_error "Can't read configuration file $cfg_file!\n";
	# She loves me!
	while($_ = <CONF>){
		SWITCH:{
			/^dest_format=(.*)/i && do{
				$1 =~ /^(jpeg|tiff)$/i or yaica_error "Option 'dest_format' in configuration file has illegal value '$1'! Must be 'jpeg' or 'tiff'.\n";
				$cfg{'dest_format'} = lc $1;
				last SWITCH;
			};
			/^dest_dir=(.*)/i && do{
				$cfg{'dest_dir'} = $1;
				last SWITCH;
			};
			/^ignore_convert=(.*)/i && do{
				$1 =~ /^(yes|no)/i or yaica_error "Option 'ignore_convert' in configuration file has illegal value '$1'! Must be 'yes' or 'no'.\n";
				$cfg{'ignore_convert'} = $yesno{$1};
				last SWITCH;
			};
			/^copy=(.*)/i && do{
				$1 =~ /^(yes|no)/i or yaica_error "Option 'copy' in configuration file has illegal value '$1'! Must be 'yes' or 'no'.\n";
				$cfg{'copy'} = $yesno{$1};
				last SWITCH;
			};
			/^grayscale=(.*)/i && do{
				$1 =~ /^(yes|no)/i or yaica_error "Option 'grayscale' in configuration file has illegal value '$1'! Must be 'yes' or 'no'.\n";
				$cfg{'grayscale'} = $yesno{$1};
				last SWITCH;
			};
			/^jpeg_quality=(.*)/i && do{
				$1 =~ /^(\d{1,3})/ or yaica_error "Option 'jpeg_quality' in configuration file has illegal value '$1'! Must be [1, 100].\n";
				$cfg{'jpeg_quality'} = $1;
				last SWITCH;
			};
			/^tiff_fax=(.*)/i && do{
				$1 =~ /^(yes|no)/i or yaica_error "Option 'tiff_fax' in configuration file has illegal value '$1'! Must be 'yes' or 'no'.\n";
				$cfg{'tiff_fax'} = $yesno{$1};
				last SWITCH;
			};
			/^(\[.*\])|#.*|^$/ && last SWITCH;
			# Empty lines, lines starting with # and section titles ([section]) are ignored!
			# In case you can't tell this from the line above:) I couldn't! Well - the second time...
			/^(\w*)=(.*)/ && do{
				# If we get here we have a nice looking line but a non-recognized option. Poor we...
				yaica_error "Bad option '$1' in configuration file!\n";
			};
			/^(.*)/ && do{
				# Too bad... Someone was sleeping while typing...
				yaica_error "Bad syntax in configuration file: '$1'!\n";
			};
		}
	}
	close CONF;
}

sub verify_cfg(){
	# Did you spell it TiFf or tiFF or tiff? Well - it doesn't matter...
	$cfg{'dest_format'} = lc $cfg{'dest_format'};
	$cfg{'dest_format'} =~ /^(jpeg|tiff)$/ or yaica_error "Bad output format '$cfg{dest_format}'! Must be 'jpeg' or 'tiff'.\n";
	#See if the directory exists. At some point I may add code to create the target directory, but who knows?
	$cfg{'dest_dir'} = glob($cfg{'dest_dir'});
	-d $cfg{'dest_dir'} or yaica_error "$cfg{'dest_dir'} is not a directory!\n";
	# Add a nice little ending slash if the poor name lacks one...
	$cfg{'dest_dir'} .= '/' if not $cfg{'dest_dir'} =~ /\/$/;
	# No log(e.pi/2) quality allowed - sorry...
	$cfg{'jpeg_quality'} = int $cfg{'jpeg_quality'};
	if ($cfg{'jpeg_quality'} <= 0 || $cfg{'jpeg_quality'} > 100){
		yaica_error "Jpeg quality '$cfg{jpeg_quality}' is invalid! Must be [1, 100].\n";
	}
}

sub read_message(){
	# See if we need to read a file or STDIN...
	if (defined $cfg{'input_file'}){
		close STDIN;
		open STDIN, '<', $cfg{'input_file'} or yaica_error "Could not read from file '$cfg{input_file}'!\n";
	}
	# It is a plane! No, it is a train!, No, it is a SPACESHIP!
	# Errr... and yet - not even a spaceship...
	my $message = join "", <STDIN> or yaica_error "Could not read from standard input!\n";
	return \$message;
	# <=>    <=>    <=>
	# But still, they come...
}

our $match = qr/(image\/(jpeg|pjpeg|tiff|gif|png|bmp|x-bmp))/o;

sub get_images($$){
	my $cur = shift;
	my $result = shift;
	my @parts = $cur->parts;
	if ($cur != $parts[0]){
	# When we point back at ourselves this means we are up against the wall
	# and have nowhere to go...
		foreach (@parts){
			get_images($_, $result);
		}
	}elsif ($cur->content_type =~ $match){
		# Come on! Push the button, push the button!
		push(@{$result}, $cur);
	}
	# Not that button!!!
}

sub store_image($$){
	my $img = shift;
	my $name = shift;
	my $type = $img->content_type;
	$type =~ $match;
	$type = $2;
	$type = 'bmp' if $type eq 'x-bmp';	# If there are more of these out there, I don't care!
	$type = 'jpeg' if $type eq 'pjpeg';
	if ($cfg{'copy'}){
		# If we just duplicate the original files, we need the propper extensions...
		$name .= '.jpg' if $type eq 'jpeg';
		$name .= '.tif' if $type eq 'tiff';
		$name .= '.'.$type if $type =~ /bmp|png|gif/;
	}else{
		# Well - we need them anyway:)
		$cfg{'dest_format'} eq 'tiff' and $name .= '.tif' or $name .= '.jpg';
	}
	$name = $cfg{'dest_dir'}.$name;
	if ($cfg{'copy'} || $type eq $cfg{'dest_format'} && $cfg{'ignore_convert'}){
		# Do not do any convertions but just duplicate the attached image.
		open (OUT, '>', $name) or yaica_error "Could not open file $name for writing!\n";
		binmode OUT;
		print OUT $img->body or yaica_error "Could not write to file $name!\n";
		close OUT;
	}else{
		# Convert image format and/or apply other otions...
		my $conv = new Image::Magick('magick'=>$type);
		my $err;
		$err = $conv->BlobToImage($img->body);
		yaica_error "ImageMagick: $err\n" if $err =~ /Exception 4\d\d/;
		my %params = ('filename'=>$name);
		$params{'compression'} = 'JPEG';
		$params{'quality'} = $cfg{'jpeg_quality'} if $cfg{'dest_format'} eq 'jpeg';
		$params{'type'} = 'Grayscale' if $cfg{'grayscale'} && not $cfg{'tiff_fax'};
		($params{'type'}, $params{'compression'}) = ('Bilevel', 'Fax') if $cfg{'dest_format'} eq 'tiff' && $cfg{'tiff_fax'};
		$err = $conv->Write(%params);
		yaica_error "ImageMagick: $err\n" if $err =~ /Exception 4\d\d/; 
	}
}

sub form_prefix($){
	my $mail = shift;
	my $from = $mail->header('From');
	my $id = $mail->header('Message-Id');
	$from =~ /(\w+((\.|-|\+)\w+)*)@(\w+(\.\w+)+)/;
	$from = "$1".'@'."$4";
	# Hmmm... which way would be better?
	$id =~ s/\D//g if $^O eq 'MSWin32'; # Strip some nasty characters...
	#$id = time if $id eq '';
	return $from."-".$id;
}

sub main(){
	read_cfg();
	get_args();
	verify_cfg();
	my $mail = Email::MIME->new(${read_message()}) or yaica_error "Could not parse input!\n";
	# It is really bad that we can't understand if the input is good or not quite...
	# Do some guessing...
	yaica_error "Bad input!\n" if $mail->content_type eq "" || $mail->header('From') eq "";
	$message_id = $mail->header('Message-Id');
	my @images;
	get_images($mail, \@images);
	my $pref = form_prefix($mail);
	my $count = 0;
	foreach(@images){
		$count++;
		store_image($_, $pref."-$count");
	}
}

main::main();

# It is the End Of All Hope...
