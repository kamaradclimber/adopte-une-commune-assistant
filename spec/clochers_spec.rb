# frozen_string_literal: true

require 'rspec'
require_relative '../adopte-une-commune-assistant'

RSpec.describe 'clochers' do
  describe 'extract_church_names' do
    context 'when there is a single response' do
      it 'returns a single name' do
        body = File.read(File.join(__dir__, 'single_result.htm'))
        expect(extract_church_names(body)).to eq ['Église Saint-Denis']
      end
    end

    context 'when there are multiple related cities' do
      pending 'works' do
        body = File.read(File.join(__dir__, 'multi_communes.htm'))
        expect(extract_church_names(body)).to eq ['...']
      end
    end

    context 'when there are multiple buildings in the city' do
      it 'works ' do
        body = File.read(File.join(__dir__, 'multi_buildings.htm'))
        expect(extract_church_names(body)).to eq [
          "Église de l'Assomption-de-la-Bienheureuse-Vierge-Marie dite aussi Notre-Dame des Hautes-Forêts",
          'Chapelle Saint-Jacques'
        ]
      end
    end
  end
end
