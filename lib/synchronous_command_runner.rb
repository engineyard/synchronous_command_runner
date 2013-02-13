require 'thread'

module SynchronousCommandRunner
  class ProcessStillRunning < StandardError; end

  # Runs +command+ in a separate thread.
  def start
    activate
    @process_should_stop_mutex.synchronize do
      @process_should_stop = false
    end
    process_worker_thread
    process_monitor_thread
  end

  # Stops +command+ with +SIGTERM+ and +SIGINT+.
  #
  # Postconditions: Any started command will be stopped or a
  # +ProcessStillRunning+ exception will be raised.
  #
  # TODO - send SIGTERM, then SIGINT if SIGTERM fails to quit.
  def stop
    STDERR.puts "#{short_inspect} stopping" if ENV['VERBOSE']
    @process_should_stop_mutex.synchronize do
      @process_should_stop = true
    end
    @process_monitor_thread && @process_monitor_thread.join
    raise ProcessStillRunning, "#{short_inspect} failed to kill." if running?
    @process_monitor_thread = nil
  end

  def running?
    return false if !@process_worker_pid
    Process.kill(0, @process_worker_pid)
    true
  rescue Errno::ESRCH => e
    false
  end

  def short_inspect
    "#<#{self.class.to_s}:#{object_id} pid=#{@process_worker_pid}>"
  end

  # Kill all known instances of +SynchronousCommandRunner+.
  def self.kill_all_jobs
    (@instances || []).select(&:running?).each do |obj|
      begin
        obj.stop
      rescue ProcessStillRunning
        warn "Unable to kill #{obj.short_inspect}."
      end
    end
  end

  private
  def activate
    return if @_activated
    SynchronousCommandRunner.register_instance(self)
    @process_should_stop ||= false
    @process_should_stop_mutex ||= Mutex.new
    @_activated = true
  end

  def process_should_stop?
    @process_should_stop
  end

  def process_monitor_thread
    # TODO
    # use a queue that blocks, not a tight polling loop
    # edge case - what happens in the worker thread ends?
    # maybe the process worker thread should stick a message in the queue
    STDERR.puts "#{short_inspect} monitoring started" if ENV['VERBOSE']
    @process_monitor_thread ||= Thread.new do
      while true do
        if process_should_stop?
          begin
            STDERR.puts "#{short_inspect}: sending TERM" if ENV['VERBOSE']
            Process.kill("TERM", @process_worker_pid) if @process_worker_pid
            STDERR.puts "#{short_inspect}: sending INT" if ENV['VERBOSE']
            Process.kill("INT", @process_worker_pid) if @process_worker_pid
          rescue Errno::ESRCH => e
            # If process doesn't exist, just move along.
          end
          STDERR.puts "#{short_inspect}: waiting on thread" if ENV['VERBOSE']
          process_worker_thread.join
          STDERR.puts "#{short_inspect}: joined" if ENV['VERBOSE']
          @process_worker_thread = nil
          break
        else
          # nop
        end

        sleep 0.1
      end
    end
  end

  def process_worker_thread
    raise ArgumentError, "#{self.inspect} must define #command" unless respond_to?(:command)
    raise ArgumentError, "#{command.inspect} must be a single command" if command =~ /&&/ || command =~ /;/

    @process_worker_thread ||= Thread.new do
      STDERR.puts "#{short_inspect} worker thread started" if ENV['VERBOSE']

      err, out = nil, nil
      SynchronousCommandRunner.command_launching_mutex.synchronize do
        set_environment if respond_to?(:set_environment)
        out = File.open(File.join(Rails.root, 'log', "#{self.class.name}-#{object_id}.out.log"), 'a')
        err = File.open(File.join(Rails.root, 'log', "#{self.class.name}-#{object_id}.err.log"), 'a')
        SynchronousCommandRunner.logfiles.append(out)
        SynchronousCommandRunner.logfiles.append(err)
      end

      @process_worker_pid = fork
      if @process_worker_pid
        Process.waitpid @process_worker_pid
      else
        STDERR.reopen(err)
        STDERR.sync = true
        STDOUT.reopen(out)
        STDOUT.sync = true
        Dir.chdir(Rails.root)
        exec command
      end
      true
    end
  end

  def self.command_launching_mutex
    @command_launching_mutex ||= Mutex.new
  end

  def self.logfiles
    @logfiles ||= Array.new
  end

  def self.register_instance(obj)
    @instances ||= []
    @instances << obj
  end
end

RSpec.configure do |config|
  # Do our best to kill absolutely everything.
  config.after(:suite) { SynchronousCommandRunner.kill_all_jobs }
  config.before(:each) do
    SynchronousCommandRunner.logfiles.each do |f|
      f.flush
      f.seek(0, IO::SEEK_END)
      f.puts "SynchronousCommandRunner.log [#{Time.new.to_s}] -- #{example.full_description}"
      f.flush
    end
  end
  config.after(:each) do
    SynchronousCommandRunner.logfiles.each do |f|
      f.flush
      f.seek(0, IO::SEEK_END)
      f.puts "SynchronousCommandRunner.log [#{Time.new.to_s}] -- #{example.full_description} -- END"
      f.flush
    end
  end
end

Thread.abort_on_exception = true
