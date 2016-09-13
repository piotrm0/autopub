if (scalar(@ARGV) != 1) {
  die "Configuration file not specified."
} else {
  require $ARGV[0];
}

my $URL_ROOT   = $Autopub::Config::URL_ROOT;
my $SITE_TITLE = $Autopub::Config::SITE_TITLE;

my $DIR_TARGET        = $Autopub::Config::DIR_TARGET;
my $DIR_SOURCE        = $Autopub::Config::DIR_SOURCE;
my $DIR_SOURCE_COMMON = $Autopub::Config::DIR_SOURCE_COMMON;
my $FILE_SOURCE_BIB   = $Autopub::Config::FILE_SOURCE_BIB;

my $DEFAULT_AUTHOR_ICON  = $Autopub::Config::DEFAULT_AUTHOR_ICON;
my $DEFAULT_PROJECT_ICON = $Autopub::Config::DEFAULT_PROJECT_ICON;

use Text::BibTeX;
use HTML::Template;
use File::Basename;

use Data::Dumper;
use strict;

setup_dirs();
my $all = compile_entries();
my @files = (@{gen_page_all_papers($all)},
#             @{gen_page_recent_papers($all)},
             @{gen_piece_summary($all)},
             @{gen_pages_paper($all)},
#             @{gen_pages_author($all)},
#             @{gen_pages_generic("project.html.tmpl", "$DIR_TARGET/projects", $all->{projects})},
             @{gen_pages_generic("keyword.html.tmpl", "$DIR_TARGET/keywords", $all->{keywords})},
             @{gen_page_template("style.css.tmpl", "$DIR_TARGET/style.css")},
             @{gen_page_template("style_include.css.tmpl", "$DIR_TARGET/style_include.css")},
            );

foreach my $pair (@files) {
  my $filename = $pair->{filename};
  my $content = $pair->{content};
  write_file($filename, $content);
}

sub rel_url {
  my ($loc) = @_;

  if ($URL_ROOT eq "") {
    return $loc;
  } elsif ($URL_ROOT =~ m/^.+\/$/) {
    return $URL_ROOT . $loc;
  } else {
    return $URL_ROOT . "/" . $loc;
  }
}

sub run_cmd {
  my ($cmd) = @_;
  print "running: $cmd\n";
  return `$cmd`;
}

sub write_file {
  my ($filename, $content) = @_;

  my ($name, $path, $suffix) = fileparse($filename);

  if (! -e $path) {
    run_cmd("mkdir $path");
  }

  print "writing $filename ...\n";

  open (my $fh, ">$filename") or die ("cannot open $filename for writing\n");
  print $fh $content;
  close ($fh);
}

sub make_dir {
  my ($dirname) = @_;
  run_cmd("mkdir -p $dirname");
}

sub setup_dirs {
  my @dirs = ($DIR_TARGET,
              map {"$DIR_TARGET/$_/"}
              ("documents", "graphics",
               "keywords",
#               "papers", "authors",
#               "projects"
              ));

  foreach my $dir (@dirs) {
    if (! -e $dir) {
      make_dir($dir);
    }
  }

  foreach my $dir ("documents", "graphics") {
    run_cmd("cp -R $DIR_SOURCE/$dir/* $DIR_TARGET/$dir/");
    run_cmd("cp -R $DIR_SOURCE_COMMON/$dir/* $DIR_TARGET/$dir/");
  }
}

sub compile_entries {
  my $bibsrc  = $FILE_SOURCE_BIB;

  my $bibfile = new Text::BibTeX::File $bibsrc or die "$bibsrc: $!\n";

  my $entries  = {};
  my $keywords = {};
  my $authors  = {};
  my $projects = {};

  my @rest;

  while (my $entry = new Text::BibTeX::Entry $bibfile) {
    next unless $entry->parse_ok;
    my $type = $entry->type;

    if ($type eq "author") {
      my $temp = hash_of_author_entry($entry);
      $authors->{$temp->{linkname}} = $temp;
    } elsif ($type eq "project") {
      my $temp = hash_of_project_entry($entry);
      $projects->{$temp->{linkname}} = $temp;
    } else {
      push @rest, $entry;
    }
  }

  $bibfile->close;

  foreach my $entry (@rest) {
    next unless $entry->parse_ok;
    my $type = $entry->type;
    next if $type eq 'string';
    next if $type eq 'author';

    my $data = hash_of_paper_entry($authors, $keywords, $projects, $entry);
    $entries->{$data->{linkname}} = $data;

    my $title = $data->{title};
    my @authors = @{$data->{authors_list}};
    my @keywords = @{$data->{keywords_list}};
    my @projects = @{$data->{projects_list}};

    foreach my $author (@authors) {
      push_hash($author, "papers_list", $data);

      foreach my $keyword (@keywords) {
        push_hash($keyword, "authors_list", $author);
        push_hash($author, "keywords_list", $keyword);
      }
      foreach my $project (@projects) {
        push_hash($project, "authors_list", $author);
        push_hash($author, "projects_list", $project);
      }
    }

    my $venue = $data->{venue};

    foreach my $keyword (@keywords) {
      $keywords->{$keyword->{linkname}} = $keyword;

      push_hash($keyword, "papers_list", $data);

      foreach my $project (@projects) {
        push_hash($project, "keywords_list", $keyword);
        push_hash($keyword, "projects_list", $project);
      }
    }

    foreach my $project (@projects) {
      push_hash($project, "papers_list", $data);
    }
  }

  return {entries => $entries,
          authors => $authors,
          projects => $projects,
          keywords => $keywords,
         };
}

sub get_template {
  my ($name) = @_;
  my $template = HTML::Template->new(filename => "$DIR_SOURCE_COMMON/templates/$name",
                                     die_on_bad_params => 0,
                                     global_vars       => 1,
                                     loop_context_vars => 1,
                                    );

  $template->param(root      => $URL_ROOT,
                   sitetitle => $SITE_TITLE,
                  );


  return $template;
}

my $month_order = {"january"   => 1,
                   "february"  => 2,
                   "march"     => 3,
                   "april"     => 4,
                   "may"       => 5,
                   "june"      => 6,
                   "july"      => 7,
                   "august"    => 8,
                   "september" => 9,
                   "october"   => 10,
                   "november"  => 11,
                   "december"  => 12};

sub cmp_months {
  return lc($month_order->{$a}) <=> lc($month_order->{$b});
}

sub cmp_papers {
  my $temp = $a->{year} <=> $b->{year};
  if ($temp != 0) { return $temp; };
  return cmp_months($a->{month}, $b->{month});
}

sub cmp_names {
  return $a->{name} cmp $b->{name};
}

sub sort_lists {
  my ($element) = @_;

  if (defined $element->{papers_list}) {
    $element->{papers_list} = [reverse sort cmp_papers @{$element->{papers_list}}];
    my $cyear = "";

    foreach my $paper (@{$element->{papers_list}}) {
      if ($paper->{year} ne $cyear) {
        $cyear = $paper->{year};
        $paper->{_year_mark} = $cyear;
      } else {
        $paper->{_year_mark} = 0;
      }
    }
  }

  if (defined $element->{keywords_list}) {
    $element->{keywords_list} = [sort cmp_names @{$element->{keywords_list}}];
  }

  if (defined $element->{projects_list}) {
    $element->{projects_list} = [sort cmp_names @{$element->{projects_list}}];
  }
}

sub sort_authors {
  my ($element) = @_;

  my $authors = $element->{authors_list};

  die("not implemented");
}

sub bibtex_string {
  my ($temp) = @_;

  my $entry = new Text::BibTeX::Entry ($temp->print_s) or die "could not make copy\n";

  my @keys = $entry->fieldlist;

  foreach my $key (@keys) {
    if ($key =~ m/^_/) {
      $entry->delete($key);
    }
  }

  return ($entry->print_s);
}

sub gen_pages_paper {
  my ($all) = @_;

  my $entries = $all->{entries} or die();

  my $ret = [];

  foreach my $entry (values %$entries) {
    my $template = get_template("paper.html.tmpl");

    sort_lists($entry);

    $template->param(%$entry);
    $template->param(bibtex => bibtex_string($entry->{entry}));
    # note: cannot generate these ahead of time as printing
    #       entries somehow screws up the reading of a bibtex file later

    push (@$ret, {filename => "$DIR_TARGET/papers/$entry->{key}.html",
                  content => $template->output()});
  }

  return $ret;
}

sub gen_pages_author {
  my ($all) = @_;

  my $authors = $all->{authors} or die();
  #my $by_author = $all->{by_author} or die();

  my $ret = [];

  foreach my $author (values %$authors) {
    next unless $author->{is_member};

    #my $pubs = $by_author->{$author->{linkname}};

    my $template = get_template("author.html.tmpl");

    sort_lists($author);

    $template->param(%$author);
    #$template->param(papers_list => $pubs);

    push (@$ret, {filename => "$DIR_TARGET/authors/$author->{linkname}.html",
                  content => $template->output()});
  }

  return $ret;
}

sub gen_pages_project {
  my ($all) = @_;

  my $projects = $all->{projects} or die();

  my $ret = [];

  foreach my $project (values %$projects) {
    my $project_linkname = $project->{linkname};

    my $template = get_template("project.html.tmpl");

    sort_lists($project);

    $template->param(%$project);

    push (@$ret, {filename => "$DIR_TARGET/projects/$project_linkname.html",
                  content => $template->output()});
  }

  return $ret;
}

sub gen_pages_generic {
  my ($template_file, $webdir, $elements) = @_;

  my $ret = [];

  foreach my $element (values %$elements) {
    my $template = get_template($template_file);

    my $linkname = $element->{linkname};

    sort_lists($element);

    $template->param(%$element);

    push (@$ret, {filename => "$webdir/$linkname.html",
                  content => $template->output()});
  }

  return $ret;
}

sub gen_page_template {
  my ($template_file, $target_file) = @_;

  my $template = get_template($template_file);

  return [{filename => $target_file,
           content => $template->output()}];
}

sub gen_page_recent_papers {
  my ($all) = @_;

  my $entries = $all->{entries} or die();
  my $keywords = $all->{keywords} or die();
  my $projects = $all->{projects} or die();

  my $template = get_template("papers.html.tmpl");

  my $temp = {"papers_list"   => [values %$entries],
              "keywords_list" => [values %$keywords],
              "projects_list" => [values %$projects],
             };

  sort_lists($temp);

  $template->param(%$temp);

  return [{filename => "$DIR_TARGET/papers.html",
           content => $template->output()
          }];
}

sub gen_piece_summary {
  my ($all) = @_;

  my $entries  = $all->{entries}  or die();
  my $keywords = $all->{keywords} or die();
  my $projects = $all->{projects} or die();

  my $template = get_template("page_piece_summary.html.tmpl");

  my $temp = {"papers_list"   => [values %$entries],
              "keywords_list" => [values %$keywords],
              "projects_list" => [values %$projects],
             };

  sort_lists($temp);

  $template->param(%$temp);

  return [{filename => "$DIR_TARGET/summary.shtml",
           content  => $template->output()}];
}

sub gen_page_all_papers {
  my ($all) = @_;

  my $entries  = $all->{entries}  or die();
  my $keywords = $all->{keywords} or die();
  my $projects = $all->{projects} or die();

  my $template = get_template("all_papers.html.tmpl");

  my $temp = {"papers_list"   => [values %$entries],
              "keywords_list" => [values %$keywords],
              "projects_list" => [values %$projects],
             };

  sort_lists($temp);

  $template->param(%$temp);

  return [{filename => "$DIR_TARGET/all_papers.html",
           content => $template->output()}];
}

sub hash_of_author_entry {
  my ($entry) = @_;

  my $temp = hash_of_entry($entry);

  $temp->{is_member} = 0 if ! defined $temp->{is_member};
  $temp->{is_former} = 0 if ! defined $temp->{is_former};
  $temp->{icon} = $DEFAULT_AUTHOR_ICON if ! defined $temp->{icon};
  $temp->{link} = 0 if ! defined $temp->{link};

  return $temp;
}

sub hash_of_project_entry {
  my ($entry) = @_;

  my $temp = hash_of_entry($entry);

  $temp->{icon} = $DEFAULT_PROJECT_ICON if ! defined $temp->{icon};
  $temp->{link} = 0 if ! defined $temp->{link};

  return $temp;
}

sub hash_of_entry {
  my ($entry) = @_;

  my $ret = {};
  my @keys = $entry->fieldlist();

  foreach my $key (@keys) {
    $ret->{$key} = $entry->get($key);
  }

  $ret->{entry}    = $entry;
  $ret->{key}      = $entry->key;
  $ret->{linkname} = linkname_of_name($ret->{key});

  return $ret;
}

sub hash_of_paper_entry {
  my ($authors, $keywords, $projects, $entry) = @_;

  my $ret = hash_of_entry($entry);

  $ret->{authors_list}  = [map {hash_of_paper_author($authors, $_)} $entry->split('author')];
  $ret->{keywords_list} = [map {hash_of_paper_keyword($keywords, $_)} (split(/\s*,\s*/, $entry->get('_keywords')))];
  $ret->{projects_list} = [map {hash_of_paper_project($projects, $_)} (split(/\s*,\s*/, $entry->get('_projects')))];

  my $type = $entry->type;
  my $venue = "";
  my $pre = "";
  if ($type eq "techreport") {
    $venue = "TR " . $ret->{institution};
  } elsif ($type eq "inproceedings") {
    $venue = $ret->{booktitle};
    $pre = "In ";
  } elsif ($type eq "misc") {
    if (defined $ret->{submitted}) {
      $venue = "(submitted)";
    } else {
      $venue = "no venue";
    }
  } elsif ($type eq "article") {
    $venue = $ret->{journal};
    $pre = "In ";
  }
  if ($pre) {
    $venue = "$pre $venue";
  }
  if ($ret->{note} eq "To appear") {
    $venue = "(To appear) $venue";
    undef $ret->{note};
  }
  if ($ret->{note} eq "Submitted") {
    $venue = "(Submitted)";
    undef $ret->{note};
  }
  $ret->{_venue} = $venue;

  if (! defined $ret->{_link_doc}) {
    if (-e "$DIR_TARGET/documents/$ret->{key}.pdf") {
      $ret->{_link_doc} = url_rel("documents/$ret->{key}.pdf");
    } else {
      $ret->{_link_doc} = 0;
    }
  }

  return $ret;
}

sub find_author {
  my ($authors, $name) = @_;

  foreach my $author (values %$authors) {
    if ($author->{name} eq $name) {
      return $author;
    }
  }

  die "unknown author: $name\n";

}

sub hash_of_paper_author {
  my ($authors, $name) = @_;

  my $author = find_author($authors, $name);

  return $author;
}

sub hash_of_paper_project {
  my ($projects, $project_key) = @_;

  my $project = $projects->{$project_key};
  die "unknown project: $project_key\n" if ! defined $project;

  my $icon = $DEFAULT_PROJECT_ICON;

  my $project_icon = $project->{icon};
  if (defined $project_icon) {
    $icon = $project_icon;
  }

  $project->{icon} = $icon;
  $project->{linkname} = linkname_of_name($project_key);

  return $project;
}

sub linkname_of_name {
  my ($string) = @_;

  my $temp = $string;

  $temp =~ s/\s/-/g;

  return $temp;
}

sub hash_of_paper_keyword {
  my ($keywords, $keyword) = @_;

  my $linkname = linkname_of_name ($keyword);

  if (defined $keywords->{$linkname}) {
    return $keywords->{$linkname};
  }

  return {name => $keyword,
          linkname => $linkname};
}

sub push_hash {
  my ($hash, $akey, $aval) = @_;

  my $ukey = '__' . $akey;
  my $uval = $aval->{linkname};

  if (! defined $hash->{$ukey}) {
    $hash->{$ukey} = {};
  }

  if (defined $hash->{$ukey}->{$uval}) {
    return;
  }

  $hash->{$ukey}->{$uval} = 1;

  if (! defined $hash->{$akey}) {
    $hash->{$akey} = [];
  }

  push (@{$hash->{$akey}}, $aval);
}
