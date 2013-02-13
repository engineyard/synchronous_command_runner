# Synchronous Command Runner

For running commands synchronously!

## Purpose



## Installation

    gem install synchronous_command_runner

or just add `synchronous_command_runner` to your `Gemfile`.
    

## Usage

Inside your application, require `synchronous_command_runner`, then
include `SynchronousCommandRunner` in a class you'd like to imbue with
this functionality. 

On an instance of said class, just call `#start` to run the command
and `#stop` to kill it. `#running?` is also available to check if the
instance has a running command.

Before launching, `#set_environment` will be invoked (if it exists) in
order to allow the command to set environment variables.

`SynchronousCommandRunner.kill_all_jobs` is available to kill
everything `SynchronousCommandRunner` has been involved in
launching. This is useful for cases where you'd like to exit
regardless of the state of the system, like at the end of a test suite.

## Example

Here's an example of a class that's used to run Resque in a separate
process so that testing of a resque-backed application can be tested.

    require 'synchronous_command_runner'

    class RealResque
      include SynchronousCommandRunner
      include Singleton
    
      def command
        "rake environment resque:work --trace"
      end
    
      def set_environment
        ENV['RAILS_ENV'] = Rails.env
        ENV['QUEUE']     = '*'
        ENV['VVERBOSE']  = '1'
      end
    end

## Handy Bits

If you're using this as part of your test suite, add this block in
your setup code to kill everything SynchronousCommandRunner has launched.

    RSpec.configure do |config|
      # Do our best to kill absolutely everything.
      config.after(:suite) { SynchronousCommandRunner.kill_all_jobs }
    end
