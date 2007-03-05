# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2005 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}

=head1 NAME

  RT::Handle - RT's database handle

=head1 SYNOPSIS

  use RT::Handle;

=head1 DESCRIPTION


=head1 METHODS

=cut

package RT::Handle;

use strict;
use vars qw/@ISA/;

eval "use DBIx::SearchBuilder::Handle::". RT->Config->Get('DatabaseType') .";
\@ISA= qw(DBIx::SearchBuilder::Handle::". RT->Config->Get('DatabaseType') .");";

if ($@) {
    die "Unable to load DBIx::SearchBuilder database handle for '". RT->Config->Get('DatabaseType') ."'.".
        "\n".
        "Perhaps you've picked an invalid database type or spelled it incorrectly.".
        "\n". $@;
}

=head2 Connect

Connects to RT's database handle.
Takes nothing. Calls SUPER::Connect with the needed args

=cut

sub Connect {
    my $self = shift;

    if (RT->Config->Get('DatabaseType') eq 'Oracle') {
        $ENV{'NLS_LANG'} = "AMERICAN_AMERICA.AL32UTF8";
        $ENV{'NLS_NCHAR'} = "AL32UTF8";
        
    }

    $self->SUPER::Connect(
			 User => RT->Config->Get('DatabaseUser'),
			 Password => RT->Config->Get('DatabasePassword'),
			);

    $self->dbh->{LongReadLen} = RT->Config->Get('MaxAttachmentSize');
   
}

=head2 BuildDSN

Build the DSN for the RT database. doesn't take any parameters, draws all that
from the config file.

=cut

use File::Spec;

sub BuildDSN {
    my $self = shift;
# Unless the database port is a positive integer, we really don't want to pass it.
    my $db_port = RT->Config->Get('DatabasePort');
    $db_port = undef unless (defined $db_port && $db_port =~ /^(\d+)$/);
    my $db_host = RT->Config->Get('DatabaseHost');
    $db_host = undef unless $db_host;
    my $db_name = RT->Config->Get('DatabaseName');
    my $db_type = RT->Config->Get('DatabaseType');
    $db_name = File::Spec->catfile($RT::VarPath, $db_name)
        if $db_type eq 'SQLite' && !File::Spec->file_name_is_absolute($db_name);


    $self->SUPER::BuildDSN( Host       => $db_host,
			                Database   => $db_name,
                            Port       => $db_port,
                            Driver     => $db_type,
                            RequireSSL => RT->Config->Get('DatabaseRequireSSL'),
                            DisconnectHandleOnDestroy => 1,
                          );
   

}

# dealing with intial data

=head2 

=cut

sub create_db {
    my $self = shift;
    my $dbh  = shift || $self->dbh;
    my $db_type = RT->Config->Get('DatabaseType');
    my $db_name = RT->Config->Get('DatabaseName');
    print "Creating $db_type database $db_name.\n";
    if ( $db_type eq 'SQLite' ) {
        return;
    }
    elsif ( $db_type eq 'Pg' ) {
        $dbh->do("CREATE DATABASE $db_name WITH ENCODING='UNICODE'");
        if ( $DBI::errstr ) {
            $dbh->do("CREATE DATABASE $db_name") || die $DBI::errstr;
        }
    }
    elsif ( $db_type eq 'Informix' ) {
        $ENV{'DB_LOCALE'} = 'en_us.utf8';
        $dbh->do("CREATE DATABASE $db_name WITH BUFFERED LOG");
    }
    else {
        $dbh->do("CREATE DATABASE $db_name") or die $DBI::errstr;
    }
}

=head2 drop_db

=cut

sub drop_db {
    my $self = shift;
    my $dbh  = shift || $self->dbh;
    my %args = %{ shift || {}};
    my $db_type = RT->Config->Get('DatabaseType');
    my $db_name = RT->Config->Get('DatabaseName');
    my $db_host = RT->Config->Get('DatabaseHost');
    if ( $db_type eq 'Oracle' ) {
        print <<END;

To delete the tables and sequences of the RT Oracle database by running
    \@etc/drop.Oracle
through SQLPlus.

END
        return;
    }
    unless ( $args{'force'} ) {
        print <<END;

About to drop $db_type database $db_name on $db_host.
WARNING: This will erase all data in $db_name.

END
        exit unless _yesno();

    }

    print "Dropping ". $db_type ." database ". $db_name .".\n";

    if ( $db_type eq 'SQLite' ) {
        unlink $RT::VarPath.'/'.$db_name or warn $!;
        return;
    }
    $dbh->do("DROP DATABASE ". $db_name) or warn $DBI::errstr;
}

sub _yesno {
    print "Proceed [y/N]:";
    my $x = scalar(<STDIN>);
    $x =~ /^y/i;
}

=head2 insert_acl

=cut

sub insert_acl {
    my $self = shift;
    my $dbh  = shift || $self->dbh;
    my $base_path = (shift || $RT::EtcPath);
    my $db_type = RT->Config->Get('DatabaseType');

    return if $db_type eq 'SQLite';

    # XXX: this is polluting acl()
    do $base_path ."/acl.". $db_type
        || die "Couldn't find ACLs for ". $db_type .": " . $@;

    my @acl = acl($dbh);
    foreach my $statement (@acl) {
#        print STDERR $statement if $args{'debug'};
        my $sth = $dbh->prepare($statement) or die $dbh->errstr;
        unless ( $sth->execute ) {
            die "Problem with statement:\n $statement\n" . $sth->errstr;
        }
    }
    print "Done setting up database ACLs.\n";
}

=head2 insert_schema

=cut

sub insert_schema {
    my $self = shift;
    my $dbh  = shift || $self->dbh;
    my $base_path = (shift || $RT::EtcPath);
    my $db_type = RT->Config->Get('DatabaseType');

    my $file = get_version_file( $base_path . "/schema." . $db_type );
    unless ( $file ) {
        die "Couldn't find schema file in '$base_path' dir";
    }
    unless ( -f $file || -r $file ) {
        die "File '$file' doesn't exist or couldn't be read";
    }

    my (@schema);
    print "Creating database schema.\n";

    open my $fh_schema, "<$file";

    my $has_local = 0;
    open my $fh_schema_local, "<" . get_version_file( $RT::LocalEtcPath . "/schema." . $db_type )
        and $has_local = 1;

    my $statement = "";
    foreach my $line ( <$fh_schema>, ($_ = ';;'), $has_local? <$fh_schema_local>: () ) {
        $line =~ s/\#.*//g;
        $line =~ s/--.*//g;
        $statement .= $line;
        if ( $line =~ /;(\s*)$/ ) {
            $statement =~ s/;(\s*)$//g;
            push @schema, $statement;
            $statement = "";
        }
    }
    close $fh_schema; close $fh_schema_local;

    local $SIG{__WARN__} = sub {};
    my $is_local = 0; # local/etc/schema needs to be nonfatal.
    $dbh->begin_work or die $dbh->errstr;
    foreach my $statement (@schema) {
        if ( $statement =~ /^\s*;$/ ) { $is_local = 1; next; }

#        print "Executing SQL:\n$statement\n" if defined $args{'debug'};
        my $sth = $dbh->prepare($statement) or die $dbh->errstr;
        unless ( $sth->execute or $is_local ) {
            die "Problem with statement:\n$statement\n" . $sth->errstr;
        }
    }
    $dbh->commit or die $dbh->errstr;

    print "Done setting up database schema.\n";
}

=head1 get_version_file

Takes base name of the file as argument, scans for <base name>-<version> named
files and returns file name with closest version to the version of the RT DB.

=cut

sub get_version_file {
    my $base_name = shift;

    require File::Glob;
    my @files = File::Glob::bsd_glob("$base_name*");
    return '' unless @files;

    my %version = map { $_ =~ /\.\w+-([-\w\.]+)$/; ($1||0) => $_ } @files;
    my $db_version = $RT::Handle->DatabaseVersion;
    print "Server version $db_version\n";
    my $version;
    foreach ( reverse sort cmp_version keys %version ) {
        if ( cmp_version( $db_version, $_ ) >= 0 ) {
            $version = $_;
            last;
        }
    }

    return defined $version? $version{ $version } : undef;
}

sub cmp_version($$) {
    my ($a, $b) = (@_);
    my @a = split /[^0-9]+/, $a;
    my @b = split /[^0-9]+/, $b;
    for ( my $i = 0; $i < @a; $i++ ) {
        return 1 unless defined $b[$i];
        return $a[$i] <=> $b[$i] if $a[$i] <=> $b[$i];
    }
    return 0 if @a == @b;
    return -1;
}


=head2 insert_initial_data

=cut

sub insert_initial_data {
    my $self    = shift;
    my $db_type = RT->Config->Get('DatabaseType');
    RT::InitLogging();

    # connect to the db, for actual RT work
    $RT::Handle->Disconnect;
    $RT::Handle = RT::Handle->new;
    $RT::Handle->BuildDSN;
    $RT::Handle->Connect;

    #Put together a current user object so we can create a User object
    require RT::CurrentUser;
    my $CurrentUser = new RT::CurrentUser();

    print "Checking for existing system user...";
    my $test_user = RT::User->new($CurrentUser);
    $test_user->Load('RT_System');
    if ( $test_user->id ) {
        print "found!\n\nYou appear to have a functional RT database.\n"
          . "Exiting, so as not to clobber your existing data.\n";
        exit(-1);

    }
    else {
        print "not found.  This appears to be a new installation.\n";
    }

    print "Creating system user...";
    my $RT_System = RT::User->new($CurrentUser);

    my ( $val, $msg ) = $RT_System->_BootstrapCreate(
        Name     => 'RT_System',
        RealName => 'The RT System itself',
        Comments => 'Do not delete or modify this user. '
            . 'It is integral to RT\'s internal database structures',
        Creator  => '1',
        LastUpdatedBy => '1',
    );

    unless ( $val ) {
        print "$msg\n";
        exit(-1);
    }
    print "done.\n";
    $RT::Handle->Disconnect() unless $db_type eq 'SQLite';
}

=head insert_data

=cut

# load some sort of data into the database
sub insert_data {
    my $self     = shift;
    my $datafile = shift;

    #Connect to the database and get RT::SystemUser and RT::Nobody loaded
    RT::Init();

    my $CurrentUser = RT::CurrentUser->new();
    $CurrentUser->LoadByName('RT_System');

    if ( $datafile eq $RT::EtcPath . "/initialdata" ) {

        print "Creating Superuser  ACL...";

        my $superuser_ace = RT::ACE->new($CurrentUser);
        $superuser_ace->_BootstrapCreate(
                             PrincipalId => ACLEquivGroupId( $CurrentUser->Id ),
                             PrincipalType => 'Group',
                             RightName     => 'SuperUser',
                             ObjectType    => 'RT::System',
                             ObjectId      => '1' );

        print "done.\n";
    }

    # Slurp in stuff to insert from the datafile. Possible things to go in here:-
    our (@Groups, @Users, @ACL, @Queues, @ScripActions, @ScripConditions,
	   @Templates, @CustomFields, @Scrips, @Attributes, @Initial, @Final);
    local (@Groups, @Users, @ACL, @Queues, @ScripActions, @ScripConditions,
	   @Templates, @CustomFields, @Scrips, @Attributes, @Initial, @Final);

    require $datafile
      || die "Couldn't find initial data for import\n" . $@;

    if ( @Initial ) {
        print "Running initial actions...\n";
        # Don't trap errors here, as they *should* be fatal
        $_->() for @Initial;
    }
    if ( @Groups ) {
        print "Creating groups...";
        foreach my $item (@Groups) {
            my $new_entry = RT::Group->new($CurrentUser);
            my $member_of = delete $item->{'MemberOf'};
            my ( $return, $msg ) = $new_entry->_Create(%$item);
            print "(Error: $msg)" unless $return;
            print $return. ".";
            if ( $member_of ) {
                $member_of = [ $member_of ] unless ref $member_of eq 'ARRAY';
                foreach( @$member_of ) {
                    my $parent = RT::Group->new($CurrentUser);
                    if ( ref $_ eq 'HASH' ) {
                        $parent->LoadByCols( %$_ );
                    }
                    elsif ( !ref $_ ) {
                        $parent->LoadUserDefinedGroup( $_ );
                    }
                    else {
                        print "(Error: wrong format of MemberOf field."
                            ." Should be name of user defined group or"
                            ." hash reference with 'column => value' pairs."
                            ." Use array reference to add to multiple groups)";
                        next;
                    }
                    unless ( $parent->Id ) {
                        print "(Error: couldn't load group to add member)";
                        next;
                    }
                    my ( $return, $msg ) = $parent->AddMember( $new_entry->Id );
                    print "(Error: $msg)" unless ($return);
                    print $return. ".";
                }
            }
        }
        print "done.\n";
    }
    if ( @Users ) {
        print "Creating users...";
        foreach my $item (@Users) {
            my $new_entry = new RT::User($CurrentUser);
            my ( $return, $msg ) = $new_entry->Create(%$item);
            print "(Error: $msg)" unless $return;
            print $return. ".";
        }
        print "done.\n";
    }
    if ( @Queues ) {
        print "Creating queues...";
        for my $item (@Queues) {
            my $new_entry = new RT::Queue($CurrentUser);
            my ( $return, $msg ) = $new_entry->Create(%$item);
            print "(Error: $msg)" unless $return;
            print $return. ".";
        }
        print "done.\n";
    }
    if ( @CustomFields ) {
        print "Creating custom fields...";
        for my $item ( @CustomFields ) {
            my $new_entry = new RT::CustomField( $CurrentUser );
            my $values    = delete $item->{'Values'};

            my @queues;
            if ( $item->{'Queue'} ) {
                my $queue_ref = delete $item->{'Queue'};
                @queues = ref $queue_ref ? @{$queue_ref} : ($queue_ref);
                $item->{'LookupType'} = 'RT::Queue-RT::Ticket';
            }

            my ( $return, $msg ) = $new_entry->Create(%$item);
            print "(Error: $msg)\n" and next unless $return;

            foreach my $value ( @{$values} ) {
                ( $return, $msg ) = $new_entry->AddValue(%$value);
                print "(Error: $msg)\n" unless $return;
            }

            if ($item->{LookupType}) { # enable by default
                my $ocf = RT::ObjectCustomField->new($CurrentUser);
                $ocf->Create( CustomField => $new_entry->Id );
            }
       
            for my $q (@queues) {
                my $q_obj = RT::Queue->new($CurrentUser);
                $q_obj->Load($q);
                unless ( $q_obj->Id ) {
                    print "(Error: Could not find queue " . $q . ")\n";
                    next;
                }
                my $OCF = RT::ObjectCustomField->new($CurrentUser);
                ( $return, $msg ) = $OCF->Create(
                    CustomField => $new_entry->Id,
                    ObjectId    => $q_obj->Id,
                );
                print "(Error: $msg)\n" unless $return and $OCF->Id;
            }

            print $new_entry->Id. ".";
        }

        print "done.\n";
    }
    if ( @ACL ) {
        print "Creating ACL...";
        for my $item (@ACL) {

            my ($princ, $object);

            # Global rights or Queue rights?
            if ( $item->{'CF'} ) {
                $object = RT::CustomField->new( $CurrentUser );
                my @columns = ( Name => $item->{'CF'} );
                push @columns, Queue => $item->{'Queue'} if $item->{'Queue'} and not ref $item->{'Queue'};
                $object->LoadByName( @columns );
            } elsif ( $item->{'Queue'} ) {
                $object = RT::Queue->new($CurrentUser);
                $object->Load( $item->{'Queue'} );
            } else {
                $object = $RT::System;
            }

            print "Couldn't load object" and next unless $object and $object->Id;

            # Group rights or user rights?
            if ( $item->{'GroupDomain'} ) {
                $princ = RT::Group->new($CurrentUser);
                if ( $item->{'GroupDomain'} eq 'UserDefined' ) {
                  $princ->LoadUserDefinedGroup( $item->{'GroupId'} );
                } elsif ( $item->{'GroupDomain'} eq 'SystemInternal' ) {
                  $princ->LoadSystemInternalGroup( $item->{'GroupType'} );
                } elsif ( $item->{'GroupDomain'} eq 'RT::System-Role' ) {
                  $princ->LoadSystemRoleGroup( $item->{'GroupType'} );
                } elsif ( $item->{'GroupDomain'} eq 'RT::Queue-Role' &&
                          $item->{'Queue'} )
                {
                  $princ->LoadQueueRoleGroup( Type => $item->{'GroupType'},
                                              Queue => $object->id);
                } else {
                  $princ->Load( $item->{'GroupId'} );
                }
            } else {
                $princ = RT::User->new($CurrentUser);
                $princ->Load( $item->{'UserId'} );
            }

            # Grant it
            my ( $return, $msg ) = $princ->PrincipalObj->GrantRight(
                                                     Right => $item->{'Right'},
                                                     Object => $object );

            if ( $return ) {
                print $return. ".";
            }
            else {
                print $msg . ".";

            }

        }
        print "done.\n";
    }

    if ( @ScripActions ) {
        print "Creating ScripActions...";

        for my $item (@ScripActions) {
            my $new_entry = RT::ScripAction->new($CurrentUser);
            my $return    = $new_entry->Create(%$item);
            print $return. ".";
        }

        print "done.\n";
    }

    if ( @ScripConditions ) {
        print "Creating ScripConditions...";

        for my $item (@ScripConditions) {
            my $new_entry = RT::ScripCondition->new($CurrentUser);
            my $return    = $new_entry->Create(%$item);
            print $return. ".";
        }

        print "done.\n";
    }

    if ( @Templates ) {
        print "Creating templates...";

        for my $item (@Templates) {
            my $new_entry = new RT::Template($CurrentUser);
            my $return    = $new_entry->Create(%$item);
            print $return. ".";
        }
        print "done.\n";
    }
    if ( @Scrips ) {
        print "Creating scrips...";

        for my $item (@Scrips) {
            my $new_entry = new RT::Scrip($CurrentUser);

            my @queues = ref $item->{'Queue'} eq 'ARRAY'? @{ $item->{'Queue'} }: $item->{'Queue'} || 0;
            push @queues, 0 unless @queues; # add global queue at least

            foreach my $q ( @queues ) {
                my ( $return, $msg ) = $new_entry->Create( %$item, Queue => $q );
            if ( $return ) {
                    print $return. ".";
                }
                else {
                    print "(Error: $msg)\n";
                }
            }
        }
        print "done.\n";
    }
    if ( @Attributes ) {
        print "Creating predefined searches...";
        my $sys = RT::System->new($CurrentUser);

        for my $item (@Attributes) {
            my $obj = delete $item->{Object}; # XXX: make this something loadable
            $obj ||= $sys;
            my ( $return, $msg ) = $obj->AddAttribute (%$item);
            if ( $return ) {
                print $return. ".";
            }
            else {
                print "(Error: $msg)\n";
            }
        }
        print "done.\n";
    }
    if ( @Final ) {
        print "Running final actions...\n";
        for ( @Final ) {
            eval { $_->(); };
            print "(Error: $@)\n" if $@;
        }
    }

    my $db_type = RT->Config->Get('DatabaseType');
    $RT::Handle->Disconnect() unless $db_type eq 'SQLite';
    print "Done setting up database content.\n";
}

=head2 ACLEquivGroupId

Given a userid, return that user's acl equivalence group

=cut

sub ACLEquivGroupId {
    my $username = shift;
    my $user     = RT::User->new($RT::SystemUser);
    $user->Load($username);
    my $equiv_group = RT::Group->new($RT::SystemUser);
    $equiv_group->LoadACLEquivalenceGroup($user);
    return ( $equiv_group->Id );
}



=head2 get_system_dsn

Returns a DSN suitable for database creates and drops
and user creates and drops.

=cut

sub get_system_dsn {
    my $db_name = RT->Config->Get('DatabaseName');
    my $db_type = RT->Config->Get('DatabaseType');
    my $dsn = get_rt_dsn();

    if ( $db_type eq 'mysql' ) {
        # with mysql, you want to connect sans database to funge things
        $dsn =~ s/dbname=\Q$db_name//;
    }
    elsif ( $db_type eq 'Pg' ) {
        # with postgres, you want to connect to template1 database
        $dsn =~ s/dbname=\Q$db_name/dbname=template1/;
    }
    elsif ( $db_type eq 'Informix' ) {
        # with Informix, you want to connect sans database:
        $dsn =~ s/Informix:\Q$db_name/Informix:/;
    }
    return $dsn;
}

=head2 get_rt_dsn

Returns DSN according to RT config.

=cut

sub get_rt_dsn {
    my $rt_handle = RT::Handle->new;
    $rt_handle->BuildDSN;
    return $rt_handle->DSN;
}



eval "require RT::Handle_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Handle_Vendor.pm});
eval "require RT::Handle_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Handle_Local.pm});

1;
