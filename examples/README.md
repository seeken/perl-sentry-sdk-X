# Sentry SDK Examples

This directory contains example scripts demonstrating various features of the Perl Sentry SDK.

## Basic Examples

### SDK Integration
- `sdk_integration_demo.pl` - Basic SDK setup and usage
- `sdk_integration_simple.pl` - Minimal integration example  
- `phase1_demo.pl` - Phase 1 implementation demo

### Error Handling and Events
- `sentry_live_test.pl` - Live error capture testing
- `test_backend_events.pl` - Backend event testing
- `deduplication_test.pl` - Event deduplication testing

### Tracing and Performance
- `simple_trace_test.pl` - Basic tracing functionality
- `test_distributed_tracing.pl` - Distributed tracing example
- `performance_optimization_demo.pl` - Performance monitoring

## Profiling Examples

### Basic Profiling
- `profiling_demo.pl` - Simple profiling introduction
- `test_basic_profiling.pl` - Basic profiling test script

### Advanced Profiling
- `advanced_profiling_demo.pl` - **Comprehensive profiling features demo**
  - Advanced configuration options
  - System monitoring and adaptive sampling  
  - Package filtering and overhead measurement
  - Performance measurement utilities

- `profiling_benchmark.pl` - **Performance impact analysis**
  - Multiple configuration benchmarking
  - Overhead measurement across workloads
  - Statistical analysis and recommendations
  - Production configuration guidance

- `real_world_profiling_example.pl` - **Complete real-world usage**
  - Environment-specific configurations (dev/staging/prod)
  - Web request profiling
  - Background job profiling  
  - Database operation profiling
  - External API integration profiling

### Custom Instrumentation
- `custom_instrumentation_demo.pl` - Custom instrumentation patterns
- `sdk_custom_instrumentation_demo.pl` - SDK-specific instrumentation

## Database and Framework Examples

### Database Integration
- `simple_db_test.pl` - Database operation tracking

### Web Frameworks

#### CGI Applications
- `cgi-app/` - CGI::Application integration
  - `my-app.cgi` - Sample CGI application
  - `start.sh` - CGI server startup script
  - `lib/WebApp.pm` - Application module

#### Mojolicious Applications  
- `mojo/` - Mojolicious framework integration
  - `mojo.yml` - Configuration file
  - `lib/mojo.pm` - Main application
  - `script/mojo` - Application script
  - `templates/` - View templates
  - `public/` - Static files

#### Scripts and Libraries
- `script/` - Standalone scripts with SDK integration
  - `my-script.pl` - Sample script
  - `lib/` - Supporting libraries

## Testing and Debugging

### Test Scripts
- `debug_log_format.pl` - Debug logging format testing
- `test_all_levels.pl` - All severity level testing (root directory)

### Live Testing
- `run_live_test.sh` - Automated live testing script
- `test_crons.sh` - Cron job testing script

## Phase Development Examples

The SDK was developed in phases, with examples for each:

- `phase1_demo.pl` - Core functionality
- `phase2_demo.pl` - Enhanced features  
- `phase3_demo.pl` - Advanced integration
- `phase4_demo.pl` - Profiling foundation
- `phase5_demo.pl` - Complete profiling
- `phase6_demo.pl` - Final optimization

## Running Examples

### Basic Usage

```bash
# Set your Sentry DSN
export SENTRY_DSN="https://your-key@sentry.io/project-id"

# Run basic examples
perl sdk_integration_simple.pl
perl profiling_demo.pl
```

### Advanced Profiling Examples

```bash  
# Run comprehensive profiling demo
perl advanced_profiling_demo.pl

# Run performance benchmarks (requires Statistics::Descriptive)
perl profiling_benchmark.pl

# Run real-world example with environment
perl real_world_profiling_example.pl development
perl real_world_profiling_example.pl production
```

### Framework Examples

```bash
# Start CGI application
cd cgi-app && ./start.sh

# Start Mojolicious application  
cd mojo && perl script/mojo daemon
```

## Dependencies

Most examples require only the base Sentry SDK. Some advanced examples need additional modules:

### Profiling Examples
- `Time::HiRes` - High resolution timing (usually in core Perl)
- `Statistics::Descriptive` - For benchmark analysis (install via CPAN)

### Web Framework Examples  
- `CGI::Application` - For CGI examples
- `Mojolicious` - For Mojo examples
- `Template::Toolkit` - For some template examples

### Database Examples
- `DBI` - Database interface
- Database-specific drivers (DBD::*)

## Configuration

### Environment Variables

- `SENTRY_DSN` - Your Sentry project DSN (required)
- `SENTRY_ENVIRONMENT` - Environment name (dev/staging/prod)
- `SENTRY_RELEASE` - Release version
- `APP_ENV` - Application environment for examples

### Example Configuration

```bash
export SENTRY_DSN="https://abc123@o123456.ingest.sentry.io/123456"
export SENTRY_ENVIRONMENT="development"  
export SENTRY_RELEASE="v1.0.0"
```

## Learning Path

### Beginner
1. Start with `sdk_integration_simple.pl`
2. Try `profiling_demo.pl` for basic profiling
3. Explore `sentry_live_test.pl` for error handling

### Intermediate  
1. Run `advanced_profiling_demo.pl` for comprehensive profiling
2. Test `real_world_profiling_example.pl` with different environments
3. Try framework examples (CGI or Mojo)

### Advanced
1. Run `profiling_benchmark.pl` to understand performance
2. Create custom instrumentation using the demo patterns
3. Integrate with your specific framework/application

## Troubleshooting

### Common Issues

**"Profiler not available"**
- Ensure `enable_profiling => 1` in SDK initialization
- Check that `profiles_sample_rate` > 0

**"No profiles in Sentry"**  
- Verify your DSN is correct
- Check sample rates aren't too low
- Ensure transactions are being created (profiling requires tracing)

**High performance overhead**
- Reduce `profiles_sample_rate` 
- Increase `sampling_interval_us`
- Enable `adaptive_sampling`

**Missing dependencies**
- Install required modules: `cpan Statistics::Descriptive Time::HiRes`
- For web examples: `cpan CGI::Application Mojolicious`

### Getting Help

- Check the main `README.md` for SDK documentation
- Review `docs/PROFILING_GUIDE.md` for profiling-specific help
- Visit the [Sentry documentation](https://docs.sentry.io/platforms/perl/) 
- Open issues on the project repository

## Contributing Examples

When adding new examples:

1. Include clear documentation in the script
2. Add error handling and meaningful output
3. Test with minimal dependencies when possible
4. Update this README with the new example
5. Consider multiple complexity levels (basic/advanced)