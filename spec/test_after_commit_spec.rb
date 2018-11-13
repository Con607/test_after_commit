require 'spec_helper'

describe TestAfterCommit do
  before do
    CarObserver.recording = false
    Car.called.clear
  end

  after do
    TestAfterCommit.enabled = true unless ENV["REAL"]
  end

  it "has a VERSION" do
    TestAfterCommit::VERSION.should =~ /^[\.\da-z]+$/
  end

  it "fires on create" do
    Car.create
    Car.called.should == [:create, :always]
  end

  it "runs callback outside of transaction" do
    car = Car.create
    car.open_transactions.should == ActiveRecord::Base.connection.open_transactions
  end

  it "works outside of transaction" do
    car = described_class.with_commits(true) { Car.create }
    car.destroy
  end if ENV["REAL"]

  it "fires on update" do
    car = Car.create
    Car.called.clear
    car.save!
    Car.called.should == [:update, :always]
  end

  it "fires on update_attribute" do
    car = Car.create
    Car.called.clear
    car.update_attribute :counter, 123
    Car.called.should == [:update, :always]
  end

  it "does not fire on rollback" do
    car = Car.new
    car.make_rollback = true
    car.save.should == nil
    Car.called.should == []
  end

  it "does not fire on ActiveRecord::RecordInvalid" do
    lambda {
      FuBear.create!
    }.should raise_exception(ActiveRecord::RecordInvalid)
    FuBear.called.should == []
  end

  it "does not fire multiple times in nested transactions" do
    Car.transaction do
      Car.transaction do
        Car.create!
        Car.called.should == []
      end
      Car.called.should == []
    end
    Car.called.should == [:create, :always]
  end

  it "fires when transaction block returns from method" do
    Car.returning_method_with_transaction
    Car.called.should == [:create, :always]
  end

  if rails42?
    it "raises errors" do
      car = Car.new
      car.raise_error = true
      lambda { car.save! }.should raise_error(RuntimeError)
    end
  else
    it "does not raises errors" do
      car = Car.new
      car.raise_error = true
      car.save!
    end
  end

  if rails42?
    context "with config.active_record.raise_in_transactional_callbacks" do
      around do |test|
        old = ActiveRecord::Base.raise_in_transactional_callbacks
        ActiveRecord::Base.raise_in_transactional_callbacks = true
        begin
          test.call
        ensure
          ActiveRecord::Base.raise_in_transactional_callbacks = old
        end
      end

      it "keeps working after an exception is raised" do
        car = Car.new
        car.raise_error = true
        lambda { car.save! }.should raise_error(RuntimeError)

        car = Car.new
        car.save!
        Car.called.should include(:always)
      end
    end
  end

  it "can do 1 save in after_commit" do
    car = Car.new
    car.do_after_create_save = true
    car.save!

    expected = if rails4?
      [:save_once, :create, :always, :save_once, :always]
    else
      [:save_once, :create, :always, :save_once, :create, :always]
    end
    Car.called.should == expected
    car.counter.should == 3
  end

  it "returns on create and on create of associations" do
    Car.create!.class.should == Car
    Car.create!.cars.create.class.should == Car unless rails4?
  end

  it "returns on create and on create of associations without after_commit" do
    Bar.create!.class.should == Bar
    Bar.create!.bars.create.class.should == Bar unless rails4?
  end

  it "calls callbacks in correct order" do
    MultiBar.create!
    MultiBar.called.should == [:two, :one]
  end

  context "Observer" do
    before do
      CarObserver.recording = true
    end

    it "should record commits" do
      Car.transaction do
        Car.create
      end
      Car.called.should == [:observed_after_commit, :create, :always]
    end

    it "should record rollbacks caused by ActiveRecord::Rollback" do
      Car.transaction do
        Car.create
        raise ActiveRecord::Rollback
      end
      Car.called.should == [:observed_after_rollback]
    end

    it "should record rollbacks caused by any type of exception" do
      begin
        Car.transaction do
          car = Car.create
          raise Exception, 'simulated error'
        end
      rescue Exception => e
        e.message.should == 'simulated error'
      end
      Car.called.should == [:observed_after_rollback]
    end

    it "should see the correct number of open transactions during callbacks" do
      skip if ENV["REAL"]
      begin
        open_txn = nil
        CarObserver.callback = proc { open_txn = Car.connection.instance_variable_get(:@test_open_transactions) }
        Car.transaction do
          Car.create
        end
        open_txn.should == 0
      ensure
        CarObserver.callback = nil
      end
    end
  end

  context "block behavior" do
    it "does not fire if turned off" do
      TestAfterCommit.enabled = false
      Car.create
      Car.called.should == []
    end

    it "always fires with when enabled by a block" do
      TestAfterCommit.enabled = false
      TestAfterCommit.with_commits(true) do
        Car.create
        Car.called.should == [:create, :always]
      end
    end

    it "defaults to with commits" do
      TestAfterCommit.with_commits do
        Car.create
        Car.called.should == [:create, :always]
      end
    end

    it "does not fire with without commits" do
      TestAfterCommit.with_commits(false) do
        Car.create
        Car.called.should == []
      end
    end
  end unless ENV["REAL"]

  context "nested after_commit" do
    it 'is executed' do
      skip if rails4? # infinite loop in REAL and fails in TEST and lots of noise when left as pending

      @address = Address.create!
      lambda {
        Person.create!(:address => @address)
      }.should change(@address, :number_of_residents).by(1)

      # one from the line above and two from the after_commit
      @address.people.count.should == 3

      @address.number_of_residents.should == 3
    end
  end
end

if rails3? && !ENV["REAL"]
  describe TestAfterCommit, "with mixed TAC enabled specs" do
    before do
      TestAfterCommit.enabled = false
      Car.called.clear
    end

    context "and a test with TAC disabled" do
      it "creates a record" do
        Car.new.save!
        Car.called.should == []
      end

      it "verifies that records are empty before each test 1" do
        connection.instance_variable_get(:@_current_transaction_records).should be_empty
      end
    end

    context "and a test with TAC enabled" do
      before { TestAfterCommit.enabled = true }

      it "creates a record and fires commit callbacks" do
        Car.new.save!
        Car.called.should == [:create, :always]
      end

      it "verifies that records are empty before each test 2" do
        connection.instance_variable_get(:@_current_transaction_records).should be_empty
      end
    end
  end
end
