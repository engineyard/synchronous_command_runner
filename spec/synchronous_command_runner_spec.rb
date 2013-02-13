require File.expand_path('../spec_helper', __FILE__)

describe SynchronousCommandRunner do
  describe 'logging' do
    it 'logs STDOUT to the IO return by #stdout'
    it 'logs STDERR to the IO return by #stderr'
  end

  describe '.kill_all_jobs' do
    it 'kills all commands that have been run'
  end

  describe '#start' do
    it 'runs the command'
  end

  describe '#stop' do
    it 'stops the process'
    it 'has no negative side effects if the command is not running'
  end
end

