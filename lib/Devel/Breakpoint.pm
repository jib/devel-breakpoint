package Devel::Breakpoint;

use strict;
use Data::Dumper;
use Object::Accessor;
use File::Spec;
use File::Spec::Unix;
use File::Alter;
use Log::Message::Simple qw[debug];

require 'perl5db.pl';
use base 'DB';

use vars qw[$VERBOSE];

BEGIN { 
    $VERBOSE = $ENV{PERL5_BP_VERBOSE} || 0;

    unshift @INC, sub { __PACKAGE__->_require( @_ ) } 

}


{   my @Objs;

    sub import { 
        my $pkg     = shift;
        my %hash    = @_;

        while( my($k,$v) = each %hash ) {
            
            ### make it into a file if it's not
            my $file = $k =~ /^[\w:]+$/ 
                        ? __PACKAGE__->_mod_to_file($k)
                        : __PACKAGE__->_file_to_unix_file($k);
                        

            my($line,$cond) = split ':', $v;
            
            my $obj = Object::Accessor->new;
            $obj->mk_accessors(qw[file line cond]);
            
            $obj->file( $file );
            $obj->line( $line );
            $obj->cond( $cond );
            
            {   my $text = "Inserting breakpoint at $file:$line";
                $text .= " if '$cond'" if $cond;
                debug( $text, $VERBOSE );
            }
            
            push @Objs, $obj;
        }
    }

    sub _require {
        my $path    = $_[-1];
        my @obj     = grep { $_->file eq $path } @Objs;
        unless( @obj ) {
            debug("No breakpoint requested for $path", $VERBOSE);
            return;
        }
        debug("Attempting to find '$path' to enter breakpoints", $VERBOSE);
        
        return;
        
        my $fh;
        my $lpath = __PACKAGE__->_file_to_local_file( $path );
        for my $entry ( @INC ) {
        
            ### skip ourselves
            next if $path eq __PACKAGE__->can('_require');

            debug("Attempting to find $path using $entry", $VERBOSE);

            ### is it a code ref?
            if( ref $entry and ref $entry eq 'CODE' ) {
         
                my $orig_fh = $entry->(@_);
                $fh = File::Alter->new( $orig_fh );
                last if $fh;

            ### just another dir
            } else {
                my $full = File::Spec->catdir( $entry, $lpath );

                $fh = File::Alter->new( $full ) if -e $full;
                last if $fh;
            }
        }
        
        ### no filehandle found?
        unless( $fh ) {
            debug("No file found for $path, giving up", $VERBOSE );
            return;
        }
            
        for my $obj (@obj) {
            my $cond = $obj->cond || 1;
            
            my $text = '$DB::single = 1 if '. $cond .';';
        
            debug( "Inserting '$text' at line " . $obj->line, $VERBOSE );
            $fh->insert( $obj->line, $text );
        }

        return $fh;
    }
}

sub _mod_to_file {
    my $class = shift;
    my $mod   = shift or return;
    
    my $file = join '', File::Spec::Unix->catfile( split '::', $mod ), '.pm';
 
    return $file;
};

sub _file_to_unix_file {
    my $class = shift;
    my $path  = shift or return;

    my (undef,$dirs,$file) = File::Spec->splitpath( $path );
    
    my $ufile = File::Spec::Unix->catfile( 
                    File::Spec->splitdir( $dirs ), $file 
                );
    
    return $ufile;
}

sub _file_to_local_file {
    my $class = shift;
    my $path  = shift or return;

    my (undef,$dirs,$file) = File::Spec::Unix->splitpath( $path );
    
    my $ufile = File::Spec->catfile( 
                    File::Spec::Unix->splitdir( $dirs ), $file 
                );
    
    return $ufile;
}



1;
