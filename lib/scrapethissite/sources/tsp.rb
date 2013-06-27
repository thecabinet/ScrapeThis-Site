require 'rubygems'
require 'mechanize'

module ScrapeThisSite
module Sources

  class ThriftSavingsPlan
    def initialize(mech, args)
      @mech = mech

      mech.get('https://www.tsp.gov/tsp/login.shtml') { |index|
        my_account_page = index.form_with(:name => 'masked') { |form|
          args.each_pair { |k,v|
            form[k] = v
          }
        }.submit

        statements_page = my_account_page.link_with(:text => 'Statements').click

        @statements = {}

        statements_page.search('#tab1Contents table.statementTable td.col1 div.statementTxt').each { |div|
          quarter = div.text
          div.search('../div[@class="statementBtns"]/a').each { |a|
            href = a['href']
            @statements[quarter] = href if href =~ /saveToDisk=true/
          }
        }

        statements_page.search('#tab2Contents table.statementTable td.col1 div.statementTxt').each { |div|
          year = div.text
          div.search('../div[@class="statementBtns"]/a').each { |a|
            href = a['href']
            @statements[year] = href if href =~ /saveToDisk=true/
          }
        }
      }
    end

    def statements
      return @statements.keys.clone
    end

    def statement(stmt)
      @mech.transact { |mech|
        file = mech.current_page.link_with(:href => @statements[stmt]).click
        return ScrapeThisSite::Util::Scrape.new(
                   :url   => file.uri.to_s,
                   :title => "#{stmt} Statement",
                   :data  => file.body,
                   :mime  => if file.filename =~ /\.pdf/i
                               'application/pdf'
                             else
                               file.response['content-type']
                             end,
                   :name  => if file.filename.downcase == 'download.pdf'
                               stmt.gsub(/\s+/, '-') + '.pdf'
                             else
                               file.filename
                             end
                 )
      }
    end
  end

end
end
