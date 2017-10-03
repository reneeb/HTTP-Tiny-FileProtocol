package HTTP::Tiny::FileProtocol;

# ABSTRACT: Add support for file:// protocol to HTTP::Tiny

use strict;
use warnings;

use HTTP::Tiny;
use File::Basename;
use LWP::MediaTypes;
use Carp;

our $VERSION = 0.01;

no warnings 'redefine';

my $orig = *HTTP::Tiny::get{CODE};

*HTTP::Tiny::get = sub {
    my ($self, $url, $args) = @_;

    @_ == 2 || (@_ == 3 && ref $args eq 'HASH')
        or _croak(q/Usage: $http->get(URL, [HASHREF])/ . "\n");

    if ( $url !~ m{\Afile://} ) {
        return $self->$orig( $url, $args || {});
    }

    my $success;
    my $status       = 599;
    my $reason       = 'Internal Exception';
    my $content      = '';
    my $content_type = 'text/plain';

    (my $path = $url) =~ s{\Afile://}{};

    if ( !-e $path ) {
        $status = 404;
        $reason = 'File Not Found';
        return _build_response( $url, $success, $status, $reason, $content, $content_type );
    }
    elsif ( !-r $path ) {
        $status = 403;
        $reason = 'Permission Denied';
        return _build_response( $url, $success, $status, $reason, $content, $content_type );
    }

    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$filesize,
       $atime,$mtime,$ctime,$blksize,$blocks)
            = stat($path);

    $status = 200;
    $success = 1;

    {
        if ( open my $fh, '<', $path ) {
            local $/;
            binmode $fh;

            $content = <$fh>;
            close $fh;

            $content_type = LWP::MediaTypes::guess_media_type( $path );
        }
        else {
            $status = 500;
            $reason = 'Internal Server Error';
            return _build_response( $url, $success, $status, $reason, $content, $content_type );
        }
    }

    return _build_response( $url, $success, $status, $reason, $content, $content_type );
};
    
sub _build_response {
    my ($url, $success, $status, $reason, $content, $content_type) = @_;

    my $bytes;
    {
        use bytes;
        $bytes = length $content;
    }

    my $response = {
        url     => $url,
        success => $success,
        status  => $status,
        ( !$success ? (reason  => $reason) : () ),
        content => $content // '',
        headers => {
            'content-type'   => $content_type,
            'content-length' => $bytes // 0,
        },
    };

    return $response;
}

1;

=head1 SYNOPSIS

    use HTTP::Tiny;
    use HTTP::Tiny::FileProtocol;
  
    my $http = HTTP::Tiny->new;
  
    my $response = $http->get( 'file:///tmp/data.txt' );

will return

    {
        success => 1,
        status  => 200,
        content => $content_of_file
        headers => {
            content_type   => 'text/plain',
            content_length => $length_of_content,
        },
    }
