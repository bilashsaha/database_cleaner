require 'database_cleaner/sequel/truncation'
require 'database_cleaner/shared_strategy'
require 'sequel'
require 'support/sequel/sequel_setup'
# XXX: use ActiveRecord's db_config (`db/config.yml`) for CI/dev convenience
require 'support/active_record/database_setup'

module DatabaseCleaner
  module Sequel
    RSpec.describe Truncation do
      it_should_behave_like "a generic strategy"
      it_should_behave_like "a generic truncation strategy"
    end

    RSpec.shared_examples 'a Sequel truncation strategy' do

      # XXX: it'd be really nice if Truncation accepted db: constructor parameter
      let(:truncation) do
        t = Truncation.new
        t.db = db
        t
      end

      context 'when several tables have data' do
        before do
          db.create_table!(:precious_stones) { primary_key :id }
          db.create_table!(:replaceable_trifles)  { primary_key :id }
          db.create_table!(:worthless_junk)  { primary_key :id }

          db[:precious_stones].insert
          db[:replaceable_trifles].insert
          db[:worthless_junk].insert
        end
        context 'by default' do
          it 'truncates all the tables' do
            t = Truncation.new
            t.db = db
            t.clean

            expect(db[:replaceable_trifles]).to be_empty
            expect(db[:worthless_junk]).to be_empty
            expect(db[:precious_stones]).to be_empty
          end
        end
        context 'when the Truncation is restricted to "only: [...]" some tables' do
          it 'truncates only the mentioned tables (and leaves the rest alone)' do
            t = Truncation.new(only: ['worthless_junk', 'replaceable_trifles'])
            t.db = db
            t.clean

            expect(db[:replaceable_trifles]).to be_empty
            expect(db[:worthless_junk]).to be_empty
            expect(db[:precious_stones].count).to eq(1)
          end
        end
        context 'when the Truncation is restricted to "except: [...]" some tables' do
          it 'leaves the mentioned tables alone (and truncates the rest)' do
            t = Truncation.new(except: ['precious_stones']) # XXX: Strings only, symbols are ignored
            t.db = db
            t.clean

            expect(db[:replaceable_trifles]).to be_empty
            expect(db[:worthless_junk]).to be_empty
            expect(db[:precious_stones].count).to eq(1)
          end
        end
      end
    end

    RSpec.shared_examples_for 'a truncation strategy without autoincrement resets' do
      it "leaves AUTO_INCREMENT index alone by default (BUG: it should be reset instead)" do
        pending
        # Jordan Hollinger made everything reset auto increment IDs
        # in commit 6a0104382647e5c06578aeac586c0333c8944492 so I'm pretty sure
        # everything is meant to reset by default.
        #
        # For Postgres, db[:mytable].truncate(restart: true) should work.
        # For SQLite, db[:sqlite_sequence].where(name: 'mytable').delete

        db.create_table!(:replaceable_trifles) { primary_key :id }
        table = db[:replaceable_trifles]
        2.times { table.insert }

        truncation.clean

        id_after_clean = table.insert
        expect(id_after_clean).to eq 1
      end
      # XXX: it'd be really nice if Truncation accepted db: constructor parameter
      let(:truncation) do
        t = Truncation.new
        t.db = db
        t
      end
    end

    RSpec.shared_examples_for 'a truncation strategy that resets autoincrement keys by default' do
      it "resets AUTO_INCREMENT primary keys" do
        db.create_table!(:replaceable_trifles) { primary_key :id }
        table = db[:replaceable_trifles]
        2.times { table.insert }

        truncation.clean

        id_after_clean = table.insert
        expect(id_after_clean).to eq 1
      end

      # XXX: it'd be really nice if Truncation accepted db: constructor parameter
      let(:truncation) do
        t = Truncation.new
        t.db = db
        t
      end
    end

    half_supported_configurations = [
      {url: 'sqlite:///',   connection_options: db_config['sqlite3']},
      {url: 'postgres:///', connection_options: db_config['postgres']},
    ]
    supported_configurations = [
      {url: 'mysql:///',    connection_options: db_config['mysql']},
      {url: 'mysql2:///',   connection_options: db_config['mysql2']}
    ]

    supported_configurations.each do |config|
      RSpec.describe "Sequel truncation (using a #{config[:url]} connection)" do
        around do |example|
          helper = SequelHelper.new(config)
          helper.setup

          example.run

          helper.teardown
        end

        let(:db) { ::Sequel.connect(config[:url], config[:connection_options]) }

        it_behaves_like 'a Sequel truncation strategy'
        it_behaves_like 'a truncation strategy that resets autoincrement keys by default'


        describe '#pre_count?' do
          subject { Truncation.new.tap { |t| t.db = db } }

          it 'should return false initially' do
            expect(subject.send(:pre_count?)).to eq false
          end

          it 'should return true if @reset_id is set and non false or nil' do
            subject.instance_variable_set(:"@pre_count", true)
            expect(subject.send(:pre_count?)).to eq true
          end

          it 'should return false if @reset_id is set to false' do
            subject.instance_variable_set(:"@pre_count", false)
            expect(subject.send(:pre_count?)).to eq false
          end
        end

        describe "relying on #pre_count_truncate_tables if asked to" do
          subject { Truncation.new.tap { |t| t.db = db } }

          it "should rely on #pre_count_truncate_tables if #pre_count? returns true" do
            subject.instance_variable_set(:"@pre_count", true)

            expect(subject).not_to receive(:truncate_tables)
            expect(subject).to receive(:pre_count_truncate_tables)

            subject.clean
          end

          it "should not rely on #pre_count_truncate_tables if #pre_count? return false" do
            subject.instance_variable_set(:"@pre_count", false)

            expect(subject).not_to receive(:pre_count_truncate_tables)
            expect(subject).to receive(:truncate_tables)

            subject.clean
          end
        end
      end
    end

    half_supported_configurations.each do |config|
      RSpec.describe "Sequel truncation (using a #{config[:url]} connection)" do
        around do |example|
          helper = SequelHelper.new(config)
          helper.setup

          example.run

          helper.teardown
        end

        let(:db) { ::Sequel.connect(config[:url], config[:connection_options]) }

        it_behaves_like 'a Sequel truncation strategy'
        it_behaves_like 'a truncation strategy without autoincrement resets'
      end
    end
  end
end
