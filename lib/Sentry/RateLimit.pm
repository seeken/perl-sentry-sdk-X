package Sentry::RateLimit;
use Mojo::Base -base, -signatures;

use Time::HiRes qw(time);

has retry_after => 0;
has rate_limits => sub { {} };  # category => expiry_time

sub is_rate_limited ($self, $category = 'error') {
    my $limit = $self->rate_limits->{$category} // 0;
    return time() < $limit;
}

sub is_globally_rate_limited ($self) {
    return time() < $self->retry_after;
}

sub update_from_headers ($self, $headers) {
    # Handle Retry-After header (global rate limit)
    if (my $retry = $headers->{'retry-after'}) {
        $self->retry_after(time() + $retry);
    }
    
    # Handle X-Sentry-Rate-Limits header (category-specific limits)
    if (my $limits = $headers->{'x-sentry-rate-limits'}) {
        $self->_parse_rate_limits($limits);
    }
}

sub _parse_rate_limits ($self, $limits_header) {
    # X-Sentry-Rate-Limits format: "60::organization:reason,2700::organization:reason"
    # Each part: "retry_after:categories:scope:reason"
    
    my @limits = split /,/, $limits_header;
    my $current_time = time();
    
    for my $limit (@limits) {
        my ($retry_after, $categories, $scope, $reason) = split /:/, $limit, 4;
        
        next unless $retry_after && $retry_after =~ /^\d+$/;
        
        my $expiry_time = $current_time + $retry_after;
        
        if ($categories) {
            # Specific categories
            my @cats = split /;/, $categories;
            for my $category (@cats) {
                $self->rate_limits->{$category} = $expiry_time;
            }
        } else {
            # All categories if no specific categories listed
            for my $category (qw(error transaction attachment session replay)) {
                $self->rate_limits->{$category} = $expiry_time;
            }
        }
    }
}

sub get_retry_after ($self, $category = 'error') {
    my $global_retry = $self->retry_after - time();
    my $category_retry = ($self->rate_limits->{$category} // 0) - time();
    
    return int(($global_retry > $category_retry ? $global_retry : $category_retry) + 0.5);
}

sub clear_expired ($self) {
    my $current_time = time();
    
    # Clear expired global rate limit
    if ($self->retry_after <= $current_time) {
        $self->retry_after(0);
    }
    
    # Clear expired category rate limits
    my $limits = $self->rate_limits;
    for my $category (keys %$limits) {
        if ($limits->{$category} <= $current_time) {
            delete $limits->{$category};
        }
    }
}

sub get_status_summary ($self) {
    my $current_time = time();
    my %summary = (
        globally_limited => $self->is_globally_rate_limited(),
        global_retry_after => $self->retry_after > $current_time ? int($self->retry_after - $current_time) : 0,
        category_limits => {},
    );
    
    for my $category (keys %{$self->rate_limits}) {
        my $expiry = $self->rate_limits->{$category};
        if ($expiry > $current_time) {
            $summary{category_limits}{$category} = int($expiry - $current_time);
        }
    }
    
    return \%summary;
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::RateLimit - Rate limiting support for Sentry SDK

=head1 SYNOPSIS

  use Sentry::RateLimit;
  
  my $rate_limit = Sentry::RateLimit->new;
  
  # Check if we're rate limited
  if ($rate_limit->is_rate_limited('error')) {
      my $retry_after = $rate_limit->get_retry_after('error');
      warn "Rate limited for $retry_after seconds";
      return;
  }
  
  # Update from HTTP response headers
  $rate_limit->update_from_headers({
      'retry-after' => 60,
      'x-sentry-rate-limits' => '60::organization:quota_exceeded',
  });

=head1 DESCRIPTION

This module handles rate limiting for the Sentry SDK, supporting both global
rate limits (via Retry-After header) and category-specific rate limits 
(via X-Sentry-Rate-Limits header).

=head1 METHODS

=head2 is_rate_limited

  my $limited = $rate_limit->is_rate_limited($category);

Returns true if the specified category is currently rate limited.

=head2 is_globally_rate_limited

  my $limited = $rate_limit->is_globally_rate_limited();

Returns true if all requests are globally rate limited.

=head2 update_from_headers

  $rate_limit->update_from_headers(\%headers);

Updates rate limit state from HTTP response headers.

=head2 get_retry_after

  my $seconds = $rate_limit->get_retry_after($category);

Returns the number of seconds to wait before retrying for the given category.

=cut
