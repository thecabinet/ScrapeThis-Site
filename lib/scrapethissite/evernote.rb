require 'digest/md5'
require 'evernote-thrift'

module ScrapeThisSite
  class Evernote
    def initialize(authToken, evernoteHost='sandbox.evernote.com')
      @authToken = authToken

      userStoreUrl = "http://#{evernoteHost}/edam/user"
      userStoreTransport = Thrift::HTTPClientTransport.new(userStoreUrl)
      userStoreProtocol = Thrift::BinaryProtocol.new(userStoreTransport)
      @userStore = ::Evernote::EDAM::UserStore::UserStore::Client.new(userStoreProtocol)

      versionOK = @userStore.checkVersion(
          "ScrapeThis|Site (Ruby)",
          ::Evernote::EDAM::UserStore::EDAM_VERSION_MAJOR,
          ::Evernote::EDAM::UserStore::EDAM_VERSION_MINOR
        )
      raise 'Evernote API is not up to date' unless versionOK

      noteStoreUrl = @userStore.getNoteStoreUrl(@authToken)
      noteStoreTransport = Thrift::HTTPClientTransport.new(noteStoreUrl)
      noteStoreProtocol = Thrift::BinaryProtocol.new(noteStoreTransport)
      @noteStore = ::Evernote::EDAM::NoteStore::NoteStore::Client.new(noteStoreProtocol)
    end

    def save(scrape)
      note = ::Evernote::EDAM::Type::Note.new
      note.notebookGuid = get_sts_notebook_guid
      note.title =  scrape.title
      note.content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                     "<!DOCTYPE en-note SYSTEM \"http://xml.evernote.com/pub/enml2.dtd\">\n" +
                     "<en-note>\n" +
                     "#{scrape.html}"

      unless scrape.data.nil?
        md5 = Digest::MD5.new

        data = ::Evernote::EDAM::Type::Data.new
        data.bodyHash = md5.digest(scrape.data)
        data.size = scrape.data.length
        data.body = scrape.data

        attrs = ::Evernote::EDAM::Type::ResourceAttributes.new
        attrs.sourceURL = scrape.url
        attrs.clientWillIndex = false
        attrs.fileName = scrape.name
        attrs.attachment = false

        resource = ::Evernote::EDAM::Type::Resource.new
        resource.data = data
        resource.mime = scrape.mime
        resource.attributes = attrs

        note.resources = [ resource ]

        note.content += "<en-media type=\"#{resource.mime}\" hash=\"#{md5.hexdigest(scrape.data)}\"/>\n"
      end

      note.content += '</en-note>'

      @noteStore.createNote(@authToken, note)
    end

    private

      def get_sts_notebook_guid
        notebooks = @noteStore.listNotebooks(@authToken)

        notebooks.each { |notebook|
          if notebook.name == 'ScrapeThis|Site'
            return notebook.guid
          end
        }

        sts_notebook = ::Evernote::EDAM::Type::Notebook.new
        sts_notebook.name = 'ScrapeThis|Site'
        return @noteStore.createNotebook(@authToken, sts_notebook).guid
      end
  end
end
