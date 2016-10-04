# encoding: utf-8
require 'spec_helper'
require "logstash/filters/dissect"

describe LogStash::Filters::Dissect do
  class LoggerMock
    attr_reader :msgs, :hashes
    def initialize()
      @msgs = []
      @hashes = []
    end

    def error(*msg)
      @msgs.push(msg[0])
      @hashes.push(msg[1])
    end

    def warn(*msg)
      @msgs.push(msg[0])
      @hashes.push(msg[1])
    end

    def debug?() true; end

    def debug(*msg)
      @msgs.push(msg[0])
      @hashes.push(msg[1])
    end

    def fatal(*msg)
      @msgs.push(msg[0])
      @hashes.push(msg[1])
    end

    def trace(*msg)
      @msgs.push(msg[0])
      @hashes.push(msg[1])
    end
  end

  describe "Basic dissection" do
    let(:config) do <<-CONFIG
      filter {
        dissect {
          mapping => {
            message => "[%{occurred_at}] %{code} %{service} %{ic} %{svc_message}"
          }
        }
      }
    CONFIG
    end

    sample("message" => "[25/05/16 09:10:38:425 BST] 00000001 SystemOut     O java.lang:type=MemoryPool,name=class storage") do
      expect(subject.get("occurred_at")).to eq("25/05/16 09:10:38:425 BST")
      expect(subject.get("code")).to eq("00000001")
      expect(subject.get("service")).to eq("SystemOut")
      expect(subject.get("ic")).to eq("O")
      expect(subject.get("svc_message")).to eq("java.lang:type=MemoryPool,name=class storage")
    end
  end

  describe "Basic dissection with datatype conversion" do
    let(:config) do <<-CONFIG
      filter {
        dissect {
          mapping => {
            message => "[%{occurred_at}] %{code} %{service} %{?ic}=%{&ic}% %{svc_message}"
          }
          convert_datatype => {
            cpu => "float"
            code => "int"
          }
        }
      }
    CONFIG
    end

    sample("message" => "[25/05/16 09:10:38:425 BST] 00000001 SystemOut cpu=95.43% java.lang:type=MemoryPool,name=class storage") do
      expect(subject.get("occurred_at")).to eq("25/05/16 09:10:38:425 BST")
      expect(subject.get("code")).to eq(1)
      expect(subject.get("service")).to eq("SystemOut")
      expect(subject.get("cpu")).to eq(95.43)
      expect(subject.get("svc_message")).to eq("java.lang:type=MemoryPool,name=class storage")
    end
  end

  describe "Basic dissection with multibyte Unicode characters" do
    let(:config) do <<-CONFIG
      filter {
        dissect {
          mapping => {
            message => "[%{occurred_at}]྿྿྿%{code}྿%{service}྿྿྿྿%{?ic}=%{&ic}%྿྿%{svc_message}"
          }
          convert_datatype => {
            cpu => "float"
            code => "int"
          }
        }
      }
    CONFIG
    end

    sample("message" => "[25/05/16 09:10:38:425 BST]྿྿྿00000001྿SystemOut྿྿྿྿cpu=95.43%྿྿java.lang:type=MemoryPool,name=class storage") do
      expect(subject.get("occurred_at")).to eq("25/05/16 09:10:38:425 BST")
      expect(subject.get("code")).to eq(1)
      expect(subject.get("service")).to eq("SystemOut")
      expect(subject.get("cpu")).to eq(95.43)
      expect(subject.get("svc_message")).to eq("java.lang:type=MemoryPool,name=class storage")
    end
  end

  describe "Basic dissection with failing datatype conversion" do
    subject(:filter) {  LogStash::Filters::Dissect.new(config)  }

    let(:message)    { "[25/05/16 09:10:38:425 BST] 00000001 SystemOut cpu=95.43% java.lang:type=MemoryPool,name=class storage" }
    let(:config)     do
      {
          "mapping" => {"message" => "[%{occurred_at}] %{code} %{service} %{?ic}=%{&ic}% %{svc_message}"},
          "convert_datatype" => {
            "ccu" => "float", # ccu field -> nil
            "code" => "integer", # only int is supported
            "other" => "int" # other field -> hash - not coercible
          }
      }
    end
    let(:event)      { LogStash::Event.new("message" => message, "other" => {}) }
    let(:loggr)      { LoggerMock.new }

    before(:each) do
      filter.class.instance_variable_set("@logger", loggr)
    end

    it "tags and log messages are created" do
      filter.register
      filter.filter(event)
      expect(event.get("code")).to eq("00000001")
      expect(event.get("tags")).to eq(["_dataconversionnullvalue_ccu_float", "_dataconversionmissing_code_integer", "_dataconversionuncoercible_other_int"])
      expect(loggr.msgs).to eq(
          [
              "Event before dissection",
              "Dissector datatype conversion, value cannot be coerced, key: ccu, value: null",
              "Dissector datatype conversion, datatype not supported: integer",
              "Dissector datatype conversion, value cannot be coerced, key: other, value: {}",
              "Event after dissection"
          ]
      )
    end
  end

  describe "dissect with skip and append" do
    let(:config) do <<-CONFIG
        filter {
          dissect {
            mapping => {
              "message" => "%{timestamp} %{+timestamp} %{+timestamp} %{logsource} %{} %{program}[%{pid}]: %{msg}"
            }
            add_field => { favorite_filter => "why, dissect of course" }
          }
        }
      CONFIG
    end

    sample("message" => "Mar 16 00:01:25 evita skip-this postfix/smtpd[1713]: connect from camomile.cloud9.net[168.100.1.3]") do
      expect(subject.get("tags")).to be_nil
      expect(subject.get("logsource")).to eq("evita")
      expect(subject.get("timestamp")).to eq("Mar 16 00:01:25")
      expect(subject.get("msg")).to eq("connect from camomile.cloud9.net[168.100.1.3]")
      expect(subject.get("program")).to eq("postfix/smtpd")
      expect(subject.get("pid")).to eq("1713")
      expect(subject.get("favorite_filter")).to eq("why, dissect of course")
    end
  end

  context "when mapping a key is not found" do
    subject(:filter) {  LogStash::Filters::Dissect.new(config)  }

    let(:message)    { "very random message :-)" }
    let(:config)     { {"mapping" => {"blah-di-blah" => "%{timestamp} %{+timestamp}"}} }
    let(:event)      { LogStash::Event.new("message" => message) }
    let(:loggr)      { LoggerMock.new }

    before(:each) do
      filter.class.instance_variable_set("@logger", loggr)
    end

    it "does not raise any exceptions" do
      expect{filter.register}.not_to raise_exception
    end

    it "dissect failure key missing is logged" do
      filter.register
      filter.filter(event)
      expect(loggr.msgs).to eq(["Event before dissection", "Dissector mapping, key not found in event", "Event after dissection"])
    end
  end

  describe "valid field format handling" do
    subject(:filter) {  LogStash::Filters::Dissect.new(config)  }
    let(:config)     { {"mapping" => {"message" => "%{+timestamp/2} %{+timestamp/1} %{?no_name} %{&no_name} %{} %{program}[%{pid}]: %{msg}"}}}

    it "does not raise an error in register" do
      expect{filter.register}.not_to raise_exception
    end
  end

  describe "invalid field format handling" do
    subject(:filter) {  LogStash::Filters::Dissect.new(config)  }

    context "when field is defined as Append and Indirect (+&)" do
      let(:config)     { {"mapping" => {"message" => "%{+&timestamp}"}}}
      it "raises an error in register" do
        msg = "org.logstash.dissect.fields.InvalidFieldException: Field cannot prefix with both Append and Indirect Prefix (+&): +&timestamp"
        expect{filter.register}.to raise_exception(LogStash::FieldFormatError, msg)
      end
    end

    context "when field is defined as Indirect and Append (&+)" do
      let(:config)     { {"mapping" => {"message" => "%{&+timestamp}"}}}
      it "raises an error in register" do
        msg = "org.logstash.dissect.fields.InvalidFieldException: Field cannot prefix with both Append and Indirect Prefix (&+): &+timestamp"
        expect{filter.register}.to raise_exception(LogStash::FieldFormatError, msg)
      end
    end
  end
end
