# frozen_string_literal: true

require 'rspec'
require_relative '../adopte-une-commune-assistant'

RSpec.describe 'clochers' do
  describe 'extract_church_name' do
    it 'works on a single name' do
      body = File.read(File.join(__dir__, 'single_result.htm'))
      expect(extract_church_name(body)).to eq 'Église Saint-Denis'
    end
  end
end
