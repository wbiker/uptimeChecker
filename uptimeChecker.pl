#!/usr/bin/perl

use Modern::Perl;
use Getopt::Std;
use DBI;
#use Data::Dumper;
use FindBin qw($Bin);
use lib "$Bin";
use SQLWrapper; # sql wrapper
use Try::Tiny;
use Data::Printer;
use File::Spec::Functions qw(catfile);

# Command line options
# -u update. this updated the database with the current date, time, hour, minute, current charge and max charge
# -l list. Lists the data in the database.
# -c create. Create the batdata table. Drops may already existing database
# -s show: show the uptime
# -m max capacity: shows the maximal capacity
# without arguments the help is printed.

if(-1 == $#ARGV) {
	help();
	exit;
}

our $opt_u;
our $opt_l;
our $opt_c;
our $opt_s;
our $opt_m;
our $opt_d;
getopts("ulcsmd") or die "Could not parse command line parameters.";

say "read command line" unless $opt_d;

my $db = catfile($Bin, 'uptime.db');
my $sql = SQLWrapper->new(connectionString => "dbi:SQLite:dbname=$db",
	user => '', # SQLite does not use user
	password => '' # and password.
	);

if($opt_c) {
    print "Do you realy want do create a new table. You know if already exists it will be delete! N/y: ";
    my $input = <STDIN>;
    chomp($input);
    if('y' eq lc($input)) {
        say "Drop Table";
        my $drop_table = "DROP TABLE batdata";
        say "Create new table";
	    my $create_table = "CREATE TABLE batdata (date VARCHAR(12), hour INTEGER, minute INTEGER, remainingCapacity INTEGER, lastFullCapacity INTEGER)";
        $sql->do($drop_table);
	    $sql->do($create_table);
    }
	exit;
}

if($opt_u) {
	say "update database...";
	
	# use a class to be able to change behavor for different battery types or OSs.
	my $bat = ReadBattery->new;
	my ($last_full_capacity, $charging_state, $remaining_capacity, $full_design_capacity) = $bat->get_bat_info;
	
	if(lc $charging_state eq "discharging") {
		# write following data in the database
		# <day.month.year> <hour> <minute> <remaining capacity> <last full capacity>
		my ($min, $hour, $day, $mon, $year) = (localtime(time))[1,2,3,4,5];
		$mon += 1;
		$year += 1900;
		$day = sprintf("%02d", $day);	# add a 0 if a single day
		$mon = sprintf("%02d", $mon);	# add a 0 in front if a single month
        
        # the remaining_capacity no longer saved in the database. I compute the percentage and store it.
        # otherwise, the remaining_capacity canged every now and then. 
        
        my $percent = $full_design_capacity / $remaining_capacity;
        $percent = 100/$percent;
        $percent = sprintf("%.2f", $percent);

		my $query = "INSERT INTO batdata VALUES(\"$day.$mon.$year\", $hour, $min, $percent, $last_full_capacity)";
		say $query;
		try {
			$sql->do($query);
		}
		catch
		{
			my $exception = $_;
			die $exception unless $exception =~ /no such table: batdata/i;
			
			my $create_table = "CREATE TABLE batdata (date VARCHAR(12), hour INTEGER, minute INTEGER, remainingCapacity INTEGER, lastFullCapacity INTEGER)";
			$sql->do($create_table);
			
			# try it again, if it this time died again I don't care
			$sql->do($query);
		};
	}
} # f param -u

if($opt_l) {
	my @rows = $sql->return_all_rows();
	# dump just the database data
	printf("%-10s %-4s %-6s %-17s %-16s\n", "Date", "hour", "minute", "remainingCapacity", "lastFullCapacity");
	for my $row (@rows) {
		printf("%-10s %-4s %-6s %-17s %-16s\n", $row->[0], $row->[1], $row->[2], $row->[3], $row->[4]);
	}
}

if($opt_s || $opt_d) {
	# read the database table information and calculates the report
	# report looks like
	# start date: <running time in minutes> <end date> <mWh consumption> <mWh consumption per minute> 
	my @data = $sql->return_all_rows();
	
	my $start_date = undef;
	my $last_remaining_capacity = 999999999; #initialze variable.
	my $start_capacity;
	my $minutes = 0;
	for my $cnt (0..$#data) {
		my $dataset = $data[$cnt]; # get the array
		if(!$start_date) {
			$start_date = $dataset->[0]; # if undef I know it is the first datarecord.
			$start_capacity = $dataset->[3]; # I use this to calculate how many mWh was consumed.
		}
		if($dataset->[3] < $last_remaining_capacity){ # as long as the new consumed mW is less than the before.
			$last_remaining_capacity = $dataset->[3];
			$minutes++;
		}
		else { # the mWh are more so the api was charged in the mean time.
			my $needed_mW = $start_capacity - $data[$cnt-1]->[3]; # fetch the conumed mWh from the record before.
			if(0 != $minutes) {
				my $mWperMin = sprintf("%d", $needed_mW / $minutes);
				say "$start_date: ", $minutes, " run till ", $dataset->[0], " needed $needed_mW mWh @ $mWperMin mWh per minute" unless $opt_d; # print
			}
			else {
				my $mWperMin = 0;
				say "$start_date: ", $minutes, " run till ", $dataset->[0], " needed $needed_mW mWh @ $mWperMin mWh per minute" unless $opt_d; # print
			}
			# battery was charging. reset variables.
			$last_remaining_capacity = $dataset->[3];
			$minutes = 0;
			$start_date = undef;
		}
	}
	# at the end of the report I print the running minutes so far.
	say "$minutes minutes run so far." if $opt_s;
    print "$minutes minutes" if $opt_d;
}# opt_s

if($opt_m) {
	my @data = $sql->return_all_rows();
	
    my @diff;
	# filter output: I am interested just in the maximal capacity:
	say "Maximal capacities:";
	my $last_value = 0;
	foreach my $recort (@data) {
		my $max_capacity = $recort->[4];
		
		if($max_capacity != $last_value) {
            push(@diff, $last_value - $max_capacity) if $last_value > $max_capacity;
			say $max_capacity;
			$last_value = $max_capacity;
		}
	}
    p @diff;
} # $opt_m
exit;

sub help {
	print <<EOH;
	usage: uptimeChecker [-u] [-l]
	-u update: writes the date, time, minutes, current charge and max charge in the database.
	-l lists: lists the data frm the database
	-s show: calculate the uptime per date plus another infos.
	-m maximum capacity: shows the maximum capacity.
	-c create: create the database and table. Warning, an already existing database and table is removed.
EOH
}

package ReadBattery;

use Modern::Perl;
use Carp qw(croak);
use File::Slurp;

sub new {
	my $class = shift;
	
	return bless {}, $class;
}

sub get_bat_info {
	my $self = shift;
	
	my $bat_path = $self->find_bat_path;
	my @file_content = read_file($bat_path."/uevent") or die "Could not read $bat_path/uevent: $!";

	my ($last_full_capacity, $charging_state, $remaining_capacity, $full_design_capacity);
	for my $line (@file_content) {
		if($line =~ /\APOWER_SUPPLY_CHARGE_FULL=(\d+)/) {
			$last_full_capacity = $1;
		}
		elsif($line =~ /\APOWER_SUPPLY_ENERGY_FULL=(\d+)/) {
			$last_full_capacity = $1;
		}
		elsif($line =~ /\APOWER_SUPPLY_STATUS=(\w+)\Z/) {
			$charging_state = $1;
		}
		elsif($line =~ /\APOWER_SUPPLY_CHARGE_NOW=(\d+)/) {
			$remaining_capacity = $1;
		}
		elsif($line =~ /\APOWER_SUPPLY_ENERGY_NOW=(\d+)/) {
			$remaining_capacity = $1;
		}
		elsif($line =~ /\APOWER_SUPPLY_CHARGE_FULL_DESIGN=(\d+)/) {
			$full_design_capacity = $1;
		}
	}

	croak "Could not find last full capacity!" unless $last_full_capacity;
	croak "Could not find charging state!" unless $charging_state;
	croak "Could not find remaining capacity!" unless $remaining_capacity;
	croak "Could not find full design capacity!" unless $full_design_capacity;
		
	return ($last_full_capacity, $charging_state, $remaining_capacity, $full_design_capacity);
}

sub find_bat_path {
	my $self = shift;
	
	my $bat_path = q(/sys/class/power_supply/BAT0);
	
	if(-e $bat_path) {
		return $bat_path;
	}
	
	croak "Could not find battery info in '$bat_path'";
}
