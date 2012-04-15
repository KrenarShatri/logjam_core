require 'json'

module Logjam

  class MongoImportBuffer

    attr_reader :iso_date_string

    def initialize(dbname, app, env, iso_date_string, processor, publisher)
      @app = app
      @env = env
      @iso_date_string = iso_date_string

      database  = Logjam.mongo.db(dbname)
      Logjam.ensure_known_database(dbname)
      @totals   = Totals.ensure_indexes(database["totals"])
      @minutes  = Minutes.ensure_indexes(database["minutes"])
      @quants   = Quants.ensure_indexes(database["quants"])
      @requests = Requests.ensure_indexes(database["requests"])

      @processor = processor
      @publisher = publisher
      @state = nil
    end

    def add(entry)
      @processor.process_request(entry)
    end

    def add_values(state)
      return if state.blank?
      if @state
        @state[:modules].merge(state[:modules])
        state[:errors].each do |mod,errors|
          (@state[:errors][mod]||=[]).concat(errors)
        end
        [:totals, :minutes, :quants].each do |k|
          merge_values(@state[k], state[k])
        end
      else
        @state = state
      end
    end

    def flush
      @publisher.publish(@state[:modules], @state[:totals], @state[:errors])
      flush_totals_buffer(@state[:totals])
      flush_minutes_buffer(@state[:minutes])
      flush_quants_buffer(@state[:quants])
    ensure
      @state = nil
    end

    private

    def merge_values(a,b)
      b.each do |mod,values|
        values.each do |k,v|
          a[k] = (a[k]||0) + v
        end
      end
    end

    UPSERT_ONE = {:upsert => true, :multi => false}

    def flush_quants_buffer(quants_buffer)
      quants = @quants
      quants_buffer.each do |(p,k,q),inc|
        quants.update({"page" => p, "kind" => k, "quant" => q}, {'$inc' => inc}, UPSERT_ONE)
      end
    end

    def flush_minutes_buffer(minutes_buffer)
      minutes = @minutes
      minutes_buffer.each do |(p,m),inc|
        minutes.update({"page" => p, "minute" => m}, {'$inc' => inc}, UPSERT_ONE)
      end
    end

    def flush_totals_buffer(totals_buffer)
      totals = @totals
      totals_buffer.each do |(p,inc)|
        totals.update({"page" => p}, {'$inc' => inc}, UPSERT_ONE)
      end
    end
  end
end
