#!/usr/bin/perl

=head1 NAME

convert.pl -- Converts Pitaval plain text files into TEI P5 XML

=head1 SYNOPSIS

convert.pl --indir=... --outdir=...

=head1 OPTIONS

=over 4

=item B<< --indir=<DIRECTORY> >>

Plain text files source directory

=item B<< --outdir=<DIRECTORY> >>

TEI P5 XML files target directory

Please note: target files names will be normalized:
non-ASCII-letters and non-digits except C<-> and C<_> will be replaced
with C<_> and filenames are cut to 100 characters plus
C<.xml> extension.

=item B<-v>

Verbose output to C<STDERR>.

=item B<-?>, B<-help>, B<-h>, B<-man>

Print help and exit.

=back

=head1 DEPENDENCIES

=over 4

=item L<File::Basename>

=item L<File::Path>

=item L<File::Temp>

=item L<FindBin>

=item L<Getopt::Long>

=item L<Pod::Usage>

=item L<XML::LibXML>

=back

=head1 AUTHOR

Frank Wiegand, L<mailto:wiegand@bbaw.de>, 2022.

=cut

use 5.030;
use warnings;

use File::Basename 'basename';
use File::Path 'make_path';
use File::Temp 'tempfile';
use FindBin;
use Getopt::Long;
use Pod::Usage;
use XML::LibXML;
use utf8;

my ($man, $help, $indir, $outdir);
my $verbose = 0;

my $template = sprintf '%s/%s', $FindBin::Bin, 'template.xml';

GetOptions(
    'indir=s'    => \$indir,
    'outdir=s'   => \$outdir,
    'template=s' => \$template,
    'v'          => \$verbose,
    'help|?'     => \$help,
    'man|h'      => \$man,
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -exitval => 0, -verbose => 2 ) if $man;

die "no --indir given, aborting" unless $indir;
die "no --outdir given, aborting" unless $outdir;

make_path( $outdir, {error => \my $err} );
if ( $err and @$err ) {
    for my $diag ( @$err ) {
        my ($file, $message) = %$diag;
        say STDERR sprintf "%s: %s", $file, $message;
    }
    die;
}

# XML parser
my $parser = XML::LibXML->new;
my $xpc = XML::LibXML::XPathContext->new;
my $ns = 'http://www.tei-c.org/ns/1.0';
$xpc->registerNs( 't', $ns );

# prepare editor nodes
my %editors;
foreach my $ed (
    ['Hitzig, Julius Eduard', '119209349'],
    ['Häring, Georg Wilhelm Heinrich', '118648071'],
    ['Vollert, Christian August Anton', '138687684'] ) {
    my ($name, $gnd) = @$ed;
    my ($last, $first) = split /,\s*/ => $name;
    my $editor = _xen('editor');
    my $persname = _xen('persName');
    $persname->setAttribute('ref', sprintf('https://d-nb.info/gnd/%s', $gnd));
    my $surname = _xen('surname');
    $surname->appendText($last);
    my $forename = _xen('forename');
    $forename->appendText($first);
    $persname->appendChild($surname);
    $persname->appendChild($forename);
    $editor->appendChild($persname);
    $editors{$last} = $editor;
}

foreach my $file ( glob sprintf('%s/*.txt', $indir) ) {
    say STDERR sprintf "parsing text file: $file" if $verbose;
    local $SIG{__WARN__} = sub { die "$file: " . $_[0] };

    my $base = basename $file, '.txt';

    my ($vol, $year, $no) = $base =~ /^Bd(\d+)_(\d{4})_(\d+)/;

    # slurp text and normalize line breaks
    open( my $fh, '<', $file ) or die $!;
    my $text = do { local $/; <$fh> };
    close $fh;
    for ( $text ) {
        s/^\f.*//gm;  # remove lines with form feed (0x0c), looks like column title
        s/\r?\n/\n/g; # windows line breaks
        s/\s+$//g;    # remove trailing spaces
    }

    open( my $text_fh, '<', \$text ) or die $!;
    my @txt;
    local $/ = "";

    # slurp text in paragraph mode
    while ( chomp(my $block = <$text_fh>) ) {
        push @txt, $block;
    }
    close $text_fh;

    # title
    my $title = extract_title( \@txt );

    # full citation
    my $bibl = sprintf '%s In: Der neue Pitaval, Bd. %d. Leipzig, %d.' => ($title =~ /\.$/ ? $title : "$title."), $vol, $year;

    # fill template
    my $source = $parser->load_xml( location => $template );
    $source->setEncoding("UTF-8");

    foreach my $el ( $xpc->findnodes('//t:title[@type="main"]', $source) ) {
        $el->appendText($title);
    }

    foreach my $el ( $xpc->findnodes('//t:biblScope[@unit="volume"]', $source) ) {
        $el->appendText($vol);
    }

    foreach my $el ( $xpc->findnodes('//t:sourceDesc/t:biblFull/t:publicationStmt/t:date', $source) ) {
        $el->appendText($year);
    }

    foreach my $el ( $xpc->findnodes('//t:sourceDesc/t:bibl', $source) ) {
        $el->appendText($bibl);
    }

    # set editors according to volume number
    my ($ts) = $xpc->findnodes('//t:sourceDesc/t:biblFull/t:titleStmt', $source);
    if ( $vol <= 30 ) {
        $ts->appendChild( $editors{Häring} );
        $ts->appendChild( $editors{Hitzig} );
    }
    else {
        $ts->appendChild( $editors{Vollert} );
    }

    my ($body) = $xpc->findnodes('/t:TEI/t:text/t:body/t:div', $source);
    my $el;

    # fill <text>
    my $i = 0;
    foreach my $p ( @txt ) {
        if ( $i != 0 and $p =~ /\n/ ) {
            # line groups
            my @lines = split /\n/ => $p;
            $el = _xen('lg');
            foreach my $line ( @lines ) {
                my $l = _xen('l');
                $l->appendText($line);
                $el->addChild($l);
                $el->addChild( _xen('lb') );
            }
        }
        elsif ( $i == 0 ) {
            # heading
            $el = _xen('head');
            $el->appendText($p =~ s/\n/ /gr);
        }
        else {
            # paragraphs
            $el = _xen('p');
            $el->appendText($p);
        }
        $body->addChild($el);
        $i++;
    }

    my $target = sprintf '%s/%s.xml', $outdir, normalize_filename($base);
    say STDERR sprintf "writing XML file: $target" if $verbose;

    open ( my $target_fh, '>:utf8', $target ) or die $!;
    print $target_fh pretty($source, $base);
    close $target_fh;
}

#######################

sub extract_title {
    my $paras = shift;

    my $title;
    foreach my $p ( @$paras ) {
        $title .= $p;
        last if $p =~ /\.$/;
    }

    for ( $title ) {
        s/\n/ /g;
        s/\s+/ /g;
    }
    return $title;
}

sub _xen { XML::LibXML::Element->new(shift) }

sub normalize_filename {
    my $str = shift;
    for ( $str ) {
        s/[^a-z0-9_-]/_/gi;
    }
    return substr($str, 0, 100)
}

sub pretty {
    my ($source, $base) = @_;

    my ($tempfh, $tempname) = tempfile();
    binmode( $tempfh, ":utf8" );
    my $xml = $source->toString;
    utf8::decode($xml);
    print $tempfh $xml;
    close $tempfh;

    my $pretty = join '' => `xmllint --encode utf8 -format "$tempname" 2>&1`;
    unlink $tempname;

    if ( $pretty =~ /\berror\s+:\s+/ ) {
#       $Data::Dumper::Sortkeys++; use Data::Dumper; warn Dumper [$source->toString, $base];
      say $pretty;
        die;
    }

    utf8::decode($pretty);
    return $pretty;
}
