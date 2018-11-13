require 'bundler/setup'
require File.expand_path '../database', __FILE__
I18n.enforce_available_locales = false

def rails3?
  ActiveRecord::VERSION::MAJOR == 3
end

def rails4?
  ActiveRecord::VERSION::MAJOR >= 4
end

def rails42?
  rails4? && ActiveRecord::VERSION::MINOR >= 2
end

require 'test_after_commit'
if ENV['REAL']
  puts 'using real transactions'
  TestAfterCommit.enabled = false
end

module ConnectionFinder
  def connection
    @connection ||=
      if rails4?
        ActiveRecord::Base.connection_handler.connection_pool_list.map(&:connection).first
      else
        ActiveRecord::Base.connection_handler.connection_pools.values.map(&:connection).first
      end
  end
end

RSpec.configure do |config|
  config.include ConnectionFinder

  unless ENV['REAL']
    config.around do |example|
      # open a transaction without using .transaction as activerecord use_transactional_fixtures does
      if ActiveRecord::VERSION::MAJOR > 3
        connection.begin_transaction :joinable => false
      else
        connection.increment_open_transactions
        connection.transaction_joinable = false
        connection.begin_db_transaction
      end

      example.call

      connection.rollback_db_transaction
      if ActiveRecord::VERSION::MAJOR == 3
        connection.decrement_open_transactions
      end
    end
  end

  config.expect_with(:rspec) { |c| c.syntax = :should }
  config.mock_with(:rspec) { |c| c.syntax = :should }
end
