package LANraragi::Plugin::Metadata::HatHGalleryinfo;

use strict;
use warnings;

use Time::Local;
use File::Basename;
use LANraragi::Model::Plugins;
use LANraragi::Utils::Logging qw(get_logger);
use LANraragi::Utils::Database qw(redis_encode redis_decode);
use LANraragi::Utils::Archive qw(is_file_in_archive extract_file_from_archive);

sub plugin_info {
    return (
        name         => "HatH galleryinfo.txt",
        type         => "metadata",
        namespace    => "hathgalleryinfo",
        author       => "chierinyan",
        version      => "0.1",
        description  => "Parses metadata from the HatH downloader generated galleryinfo.txt",
        icon         => "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI0LTA2LTA1VDE3OjI1OjQ2KzAwOjAwDhuNnAAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNC0wNi0wNVQxNzoyNTo0NiswMDowMH9GNSAAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjQtMDYtMDVUMTc6MjU6NDYrMDA6MDAoUxT/AAAAB3RFWHRsYWJlbABA69qK2wAAAaNJREFUOI3t0j9I1HEYx/HX93d1gRxJUwhFSC7q0lDhElw0NBQ2RRj9gYYjaBCCCMS8OzujJRok+jO0REtNSeBSENSSEEVlEYFQDkZkVKBlevdtUCrvTB0d+mxfnuf95nkevvzPiktYtHrGNokTgmZMII1EcNNLV9xWXp5wv5QWFwTtKjr1uosIuqyX1o86w/ZVS1ctKGzVj12iNr0+KtiuolXinei96IjgoWY5XP4bTWpkPXbiOA7jm7w7uCTlA/oETxVNqbgu0VGN1wqDTjxQMISzgr1mHJQ3iCm8mVt/BJuWFpIV3ZOzWpATPVHyFkG0BcNz5BpMVsPzb1iQQb2KUQ0asRavQLcmQb3oNYha8GzxCcdNI0qk/DSOsmAdSNmDH4IvCtI4iqvVwtS815CyrA7RZyUDstI4JmurYBKDOCk6gFuKbixwsqoUnVYwKq8O5G2Q1/S73q1Rl4Z/4bUfe3ad+6JPMg45ZaKmp8duM547Z2xp4exUdSgJ2kUDoheYEWzGDsEjX5130fflCf9MmxG1iTZKlEUjxjx2zfSi3IrOL78DdhjScQmuAAAAAElFTkSuQmCC",
        parameters   => [
            {type => "bool", desc => "Prefer filename over galleryinfo.txt for title", default_value => "1"},
            {type => "bool", desc => "Parse title for artist, group, and parody", default_value => "1"},
        ]
    );
}

sub get_tags {
    shift;
    my $lrr_info = shift;
    my $archive_path = $lrr_info->{file_path};
    my ($prefer_filename, $parse_title) = @_;

    my $logger = get_logger("HatH galleryinfo","plugins");
    $logger->info("Parsing galleryinfo.txt for " . $lrr_info->{archive_title});

    my $full_title;
    my $summary;
    my @new_tags = ();

    my $galleryinfo_path;
    if (is_file_in_archive($archive_path, "galleryinfo.txt")) {
        $galleryinfo_path = extract_file_from_archive($archive_path, "galleryinfo.txt");
        open(my $fh, '<:encoding(UTF-8)', $galleryinfo_path) or goto COMMIT;
        while (my $line = <$fh>) {
            chomp $line;
            if ((not $prefer_filename) && $line =~ /Title:\s+(.+)/) {
                $full_title = $1;
            } elsif ($line =~ /Upload Time:\s+(.+)/) {
                my $upload_time_ts = to_unix_ts($1);
                push @new_tags, "timestamp:$upload_time_ts";
            # } elsif ($line =~ /Uploaded By:\s+(.+)/) {
            #     push @new_tags, "uploader:$1";
            # } elsif ($line =~ /Downloaded:\s+(.+)/) {
            #     my $download_time_ts = to_unix_ts($1);
            #     push @new_tags, "date_downloaded:$download_time_ts";
            } elsif ($line =~ /Tags:\s+(.+)/) {
                push @new_tags, $1;
            } elsif ($line eq "Uploader's Comments:") {
                $summary = "Uploader's Comments:\n";
                while (my $comments = <$fh>) {
                    $summary .= $comments;
                }
            } else {
                $summary = $line; # get the last line when no comment exists
            }
        }
        $summary =~ s/\n+$//g;
    }

    COMMIT:
    if (defined $galleryinfo_path) { unlink $galleryinfo_path; }

    if (not defined $full_title) {
        # Run a decode to make sure we can derive tags with the proper encoding.
        my $file_path = redis_decode($lrr_info->{file_path});
        $full_title = fileparse($file_path, qr/\.[^.]*/);
    }

    my $title_partern = qr{
        ^(\((.*?)\))? # Convention
        \s*
        (\[(.*?)\])?  # Entire author field
        \s*
        ([^[(]*)      # Title
        (\((.*)\))?   # Parody
        .*?
        (\[(\d+)\])?$ # Gallery ID
    }x;
    $full_title =~ $title_partern;
    my $title = strip($5);
    if (defined $9) { push @new_tags, "eh_gid:$9"; }
    if (defined $2) { push @new_tags, "convention:$2"; }

    if ($parse_title) {
        if (defined $7) {
            foreach my $parody (split /\s*;\s*/, $7) {
                push @new_tags, "parody_original:$parody";
            }
        }
        if (defined $4) {
            # Once you give up solving the problem with regex, the problem is solved.
            my $author_str = $4;
            my @author_char = split //, $author_str;

            my $name = "";
            my $push_author = sub {
                my $is_artist = shift;
                if ($name eq "") { return; }
                $name = strip($name);
                if ($is_artist) { push @new_tags, "artist_original:$name"; }
                else { push @new_tags, "group_original:$name"; }
                $name = "";
            };

            while (my $char = shift @author_char) {
                if ($char eq "(") {
                    $push_author->(0);
                } elsif ($char ~~ [";", ")"]) {
                    $push_author->(1);
                } else {
                    $name .= $char;
                }
            }
            $push_author->(1);
        }
    }

    my $tags_str = join(", ", @new_tags);
    $logger->info("New Title: $title, New Tags: $tags_str");
    return (tags => $tags_str, title => $title, summary => $summary);
}

sub to_unix_ts {
    my ($datetime_str) = @_;
    my ($year, $month, $day, $hour, $minute) = split /\D/, $datetime_str;
    return timegm(0, $minute, $hour, $day, $month - 1, $year);;
}

sub strip {
    my $s = shift;
    $s =~ s/^\s+|\s+$//g;
    return $s;
}

1;
