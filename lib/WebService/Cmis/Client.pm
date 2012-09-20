package WebService::Cmis::Client;

=head1 NAME

WebService::Cmis::Client - Transport layer

=head1 DESCRIPTION

This is the workhorse communicating with the document manangement server
by connecting to the REST service. It provides the initial access function
to the L<repositories|WebService::Cmis::Repository>.

  use Cache::FileCache ();

  my $client = WebService::Cmis::getClient(
      url => "http://cmis.alfresco.com/service/cmis",
      user => "admin",
      password => "admin",
      cache => new Cache::FileCache({
        cache_root => "/tmp/cmis_client"
      }
    )
  );

  my $repo = $client->getRepository;

Parent class: L<REST::Client>

=cut

use strict;
use warnings;

use WebService::Cmis qw(:namespaces :utils);
use WebService::Cmis::Repository ();
use WebService::Cmis::ClientException ();
use WebService::Cmis::ServerException ();
use XML::LibXML ();
use REST::Client ();
use Data::Dumper ();
use Storable ();
use Digest::MD5  ();
use Error qw(:try);

our @ISA = qw(REST::Client);

=head1 METHODS

=over 4

=item new(%params)

Create a new WebService::Cmis::Client object. This requires
a url of the webservice api, as well as a user and password
for authentication.

Parameters:

=over 4

=item * user

=item * password

=item * url - repository url; example:

  "http://localhost:8080/alfresco/service/cmis"

=item * cache - a Cache::Cache object to be used for caching

=item * overrideCacheContrib - boolean flag to ignore any http cache control for more aggressive caching

=item * loginUrl - url used for ticket-based authentication; example:

  "http://localhost:8080/alfresco/service/api/login?u={username}&pw={password}"

=item * logoutUrl - url used for ticket-based authentication; example:

  "http://localhost:8080/alfresco/service/api/login/ticket/{ticket}"

=back

See L<REST::Client> for more options.

=cut

sub new {
  my ($class, %params) = @_;

  my $user = delete $params{user};
  my $password = delete $params{password};
  my $repositoryUrl = delete $params{url} || '';
  my $cache = delete $params{cache};
  my $overrideCacheControl = delete $params{overrideCacheControl};
  my $loginUrl = delete $params{loginUrl};
  my $logoutUrl = delete $params{logoutUrl};

  $params{follow} = 1 unless defined $params{follow}; # default to follow redirects

  my $this = $class->SUPER::new(%params);

  $this->{user} = $user;
  $this->{password} = $password;
  $this->{loginUrl} = $loginUrl;
  $this->{logoutUrl} = $logoutUrl;
  $this->{cache} = $cache;
  $this->{overrideCacheControl} = $overrideCacheControl;
  $this->{repositoryUrl} = $repositoryUrl;
  $this->{_cacheHits} = 0;

  $this->setUseragent(new BasicAuthAgent($this)); 
  $this->login;

  return $this;
}

sub DESTROY {
  my $this = shift;

  undef $this->{useragent};
  $this->_init;
  writeCmisDebug($this->{_cacheHits}." cache hits found") if $this->{cache};
}

sub _init {
  my $this = shift;

  undef $this->{_res};
  undef $this->{_cacheEntry};
  undef $this->{_cacheHits};
  undef $this->{_ticket};
  undef $this->{repositories};
  undef $this->{defaultRepository};
}

=item toString

return a string representation of this client

=cut

sub toString {
  my $this = shift;
  return "CMIS client connection to $this->{repositoryUrl}";
}

# parse a resonse coming from alfresco
sub _parseResponse {
  my $this = shift;

  #writeCmisDebug("called _parseResponse");

  my $content = $this->responseContent;
  #writeCmisDebug("content=$content");

  unless ($this->{xmlParser}) {
    $this->{xmlParser} = XML::LibXML->new;
  }

  return if !defined $content || $content eq '';
  return $this->{xmlParser}->parse_string($content);
}

=item clearCache

nukes all of the cache. calling this method is sometimes required
to work around caching effects.

=cut

sub clearCache {
  my $this = shift;
  my $cache = $this->{cache};
  return unless defined $cache;

  writeCmisDebug("clearing cache");
  return $cache->clear(@_);
}

=item purgeCache

purges outdated cache entries. call this method in case the
cache backend is able to do a kind of house keeping.

=cut

sub purgeCache {
  my $this = shift;
  my $cache = $this->{cache};
  return unless defined $cache;

  return $cache->purge(@_);
}

=item removeFromCache($path, %params)

removes an item from the cache associated with the given path
and url parameters

=cut

sub removeFromCache {
  my $this = shift;
  my $path = shift;

  my $uri = _getUri($path, @_);
  writeCmisDebug("removing from cache $uri");
  return $this->_cacheRemove($uri);
}

# internal cache layer
sub _cacheGet {
  my $this = shift;
  my $cache = $this->{cache};
  return unless defined $cache;

  my $key = $this->_cacheKey(shift);
  my $val = $cache->get($key, @_);
  return unless $val;
  return ${Storable::thaw($val)};
}

sub _cacheSet {
  my $this = shift;
  my $cache = $this->{cache};
  return unless defined $cache;

  my $key = $this->_cacheKey(shift);
  my $val = shift;
  $val = Storable::freeze(\$val);
  return $cache->set($key, $val, @_);
}

sub _cacheRemove {
  my $this = shift;
  my $cache = $this->{cache};
  return unless defined $cache;

  my $key = $this->_cacheKey(shift);
  return $cache->remove($key, @_);
}

sub _cacheKey {
  my $this = shift;
  local $Data::Dumper::Indent = 1;
  local $Data::Dumper::Terse = 1;
  local $Data::Dumper::Sortkeys = 1;

  # cache per user as data must not leak between users via the cache
  return _untaint(Digest::MD5::md5_hex(Data::Dumper::Dumper($_[0]).'::'.$this->{user})); 
}

=item get($path, %params) 

does a get against the CMIS service. More than likely, you will not
need to call this method. Instead, let the other objects to it for you.

=cut

sub get {
  my $this = shift;
  my $path = shift;

  my $url;
  if ($path) {
    $path =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus port
    if ($path =~ /^http/) {
      $url = $path;
    } else {
      $path =~ s/^\///g;
      $url = $this->{repositoryUrl};
      $url .= '/'.$path;
    }
  } else {
    $url = $this->{repositoryUrl};
  }

  my $uri = _getUri($url, @_);
  writeCmisDebug("called get($uri)");

  # do it
  $this->GET($uri);

  #writeCmisDebug("content=".$this->responseContent);

  my $code = $this->responseCode;

  return $this->_parseResponse if $code >= 200 && $code < 300;
  $this->processErrors;
}

sub _getUri {
  my $url = shift;

  my $uri = new URI($url);
  my %queryParams = ($uri->query_form, @_);
  $uri->query_form(%queryParams);

  return $uri;
}

=item request ( $method, $url, [$body_content, %$headers] )

add a cache layer on top of all network connections of the rest client

=cut

sub request {
  my $this = shift;
  my $method = shift;
  my $url = shift;

  if($this->{_cacheEntry} = $this->_cacheGet($url)) {
    writeCmisDebug("found in cache: $url");
    $this->{_cacheHits}++;
    return $this;
  }
  #writeCmisDebug("request url=$url");

  my $result = $this->SUPER::request($method, $url, @_);

  # untaint
  $this->{_res}->content(_untaint($this->{_res}->content));
  $this->{_res}->code(_untaint($this->{_res}->code));
  $this->{_res}->status_line(_untaint($this->{_res}->status_line));

  my $code = $this->responseCode;
  
  my $cacheControl = $this->{_res}->header("Cache-Control") || '';
  #writeCmisDebug("cacheControl = $cacheControl");
  $cacheControl = '' if $this->{overrideCacheControl};
  if ($cacheControl ne 'no-cache' && $code >= 200 && $code < 300 && $this->{cache}) {
    my $cacheEntry = {
      content => $this->{_res}->content,
      code => $this->{_res}->code,
      status_line => $this->{_res}->status_line,
      base => $this->{_res}->base,
    };
    $this->_cacheSet($url, $cacheEntry);
  }

  return $result;
}

=item responseContent

returns the full content of a response

=cut

sub responseContent {
  my $this = shift;

  return $this->{_cacheEntry}{content} if $this->{_cacheEntry};
  return $this->{_res}->content;
}

=item responseCode

returns the HTTP status code of the repsonse

=cut

sub responseCode {
  my $this = shift;

  return $this->{_cacheEntry}{code} if $this->{_cacheEntry};
  return $this->{_res}->code;
}

=item responseStatusLine

returns the "code message" of the response. (See HTTP::Status)

=cut

sub responseStatusLine {
  my $this = shift;

  return $this->{_cacheEntry}{status_line} if $this->{_cacheEntry};
  return $this->{_res}->status_line;
}

=item responseBase -> $uri

returns the base uri for this response

=cut

sub responseBase {
  my $this = shift;
  return $this->{_cacheEntry}{base} if $this->{_cacheEntry};
  return $this->{_res}->base;
}

sub _untaint {
  my $content = shift;
  if (defined $content && $content =~ /^(.*)$/s) {
    $content = $1;
  }
  return $content;
}

=item post($path, $payload, $contentType, %params) 

does a post against the CMIS service. More than likely, you will not
need to call this method. Instead, let the other objects to it for you.

=cut

sub post {
  my $this = shift;
  my $path = shift;
  my $payload = shift;
  my $contentType = shift;
  my %params = @_;

  $path =~ s/^\///g;

  my $url;
  if ($path) {
    $path =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus port
    if ($path =~ /^$this->{repositoryUrl}/) {
      $url = $path;
    } else {
      $path =~ s/^\///g;
      $url = $this->{repositoryUrl};
      $url .= '/'.$path;
    }
  } else {
    $url = $this->{repositoryUrl};
  }

  writeCmisDebug("called post($url)");
  $params{"Content-Type"} = $contentType;

  if ($ENV{CMIS_DEBUG}) {
    writeCmisDebug("post params:\n   * ".join("\n   * ", map {"$_=$params{$_}"} keys %params));
  }

  # do it
  $this->POST($url, $payload, \%params);

  # auto clear the cache
  $this->clearCache;

  my $code = $this->responseCode;
  return $this->_parseResponse if $code >= 200 && $code < 300;
  $this->processErrors;
}

=item put($path, $payload, $contentType, %params) 

does a put against the CMIS service. More than likely, you will not
need to call this method. Instead, let the other objects to it for you.

=cut

sub put {
  my $this = shift;
  my $path = shift;
  my $payload = shift;
  my $contentType = shift;

  $path =~ s/^\///g;

  my $url;
  if ($path) {
    $path =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus port
    if ($path =~ /^$this->{repositoryUrl}/) {
      $url = $path;
    } else {
      $path =~ s/^\///g;
      $url = $this->{repositoryUrl};
      $url .= '/'.$path;
    }
  } else {
    $url = $this->{repositoryUrl};
  }

  my $uri = _getUri($url, @_);
  writeCmisDebug("called put($uri)");

  # auto clear the cache
  $this->clearCache;

  # do it
  $this->PUT($uri, $payload,  {"Content-Type"=>$contentType});

  my $code = $this->responseCode;
  return $this->_parseResponse if $code >= 200 && $code < 300;
  $this->processErrors;
}

=item delete($url, %params)

does a delete against the CMIS service. More than likely, you will not
need to call this method. Instead, let the other objects to it for you.

=cut

sub delete {
  my $this = shift;
  my $url = shift;

  my $uri = _getUri($url, @_);
  writeCmisDebug("called delete($uri)");

  $this->DELETE($uri);

  # auto clear the cache
  $this->clearCache;

  my $code = $this->responseCode;
  return $this->_parseResponse if $code >= 200 && $code < 300;
  $this->processErrors;
}

=item processErrors 

throws a client or a server exception based on the http error code
of the last transaction.

=cut

sub processErrors {
  my $this = shift;

  my $code = $this->responseCode;
  writeCmisDebug("processError($code)");
  if ($code >= 400 && $code < 500) {
    throw WebService::Cmis::ClientException($this);
  }

  if ($code >= 500) {
    throw WebService::Cmis::ServerException($this);
    #throw Error::Simple("Server error $code: ".$this->responseStatusLine);
  }

  # default
  throw Error::Simple("unknown client error $code: ".$this->responseStatusLine);
}

=item getRepositories() -> %repositories;

returns a hash of L<WebService::Cmis::Repository> objects available at this
service. 

=cut

sub getRepositories {
  my $this = shift;

  writeCmisDebug("called getRepositories");

  unless (defined $this->{repositories}) {
    $this->{repositories} = ();

    my $doc = $this->get;
    if (defined $doc) {
      foreach my $node ($doc->findnodes('./*[local-name()="service" and namespace-uri()="'.APP_NS.'"]/*[local-name()="workspace" and namespace-uri()="'.APP_NS.'"]')) {
        my $repo = new WebService::Cmis::Repository($this, $node);
        $this->{repositories}{$repo->getRepositoryId} = $repo;

        #SMELL: not covered by the specs, might need a search which one actually is the default one
        $this->{defaultRepository} = $repo unless defined $this->{defaultRepository};
      }
    }
  }

  return $this->{repositories};
}

=item getRepository($id) -> L<$repository|WebService::Cmis::Repository>

returns a WebService::Cmis::Repository of the given ID. if
ID is undefined the default repository will be returned.

=cut

sub getRepository {
  my ($this, $id) = @_;

  $this->getRepositories;
  return $this->{defaultRepository} unless defined $id;
  return $this->{repositories}{$id};
}

=item getCacheHits() -> $num

returns the number of times a result has been fetched from the cache
instead of accessing the CMIS backend. returns undefined when no cache
is configured

=cut

sub getCacheHits {
  my $this = shift;

  return unless defined $this->{cache};
  return $this->{_cacheHits};
}

# private version of a user agent for for basic auth
{
  package BasicAuthAgent;
  our @ISA = qw(LWP::UserAgent);

  sub new {
    my $class = shift;
    my $client = shift;
    
    my $this = $class->SUPER::new(@_);
    $this->{client} = $client;
 
    return $this;
  }

  sub get_basic_credentials {
    my $this = shift;

    return ($this->{client}{user}, $this->{client}{password});
  }
}

=item login() 

logs in to the web service fetching a ticket if possible.

=cut

sub login {
  my $this = shift;

  return $this->{_ticket} if defined $this->{_ticket};
  return if !defined $this->{user};

  my $loginUrl = $this->{loginUrl};
  return unless defined $loginUrl;

  $loginUrl =~ s/{username}/$this->{user}/g;
  $loginUrl =~ s/{password}/$this->{password}/g;

  $this->{_ticket} = ''; # prevent deep recursion 

  my $doc = $this->get($loginUrl);
  $this->{_ticket} = $doc->findvalue("ticket");

  throw Error::Simple("no ticket found in response: ".$doc->toString(1))
    unless defined $this->{_ticket};

  $this->{user} = 'ROLE_TICKET';
  $this->{password} = $this->{_ticket};

  return $this->{_ticket};
}

=item logout() 

logs out of the web service deleting a ticket previously aquired

=cut

sub logout {
  my $this = shift;

  return if !defined $this->{logoutUrl} || !defined $this->{_ticket};

  my $logoutUrl = $this->{logoutUrl};
  $logoutUrl =~ s/{ticket}/$this->{_ticket}/g;

  $this->delete($logoutUrl);

  $this->_init;
}

=back

=head1 COPYRIGHT AND LICENSE

Copyright 2012 Michael Daum

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See F<http://dev.perl.org/licenses/artistic.html>.

=cut

1;
