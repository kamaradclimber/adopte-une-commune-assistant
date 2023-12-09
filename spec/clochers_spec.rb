# frozen_string_literal: true

require 'rspec'
require_relative '../adopte-une-commune-assistant'

RSpec.describe 'clochers' do
  describe 'extract_churches' do
    context 'when there is a single response' do
      let(:fake_uri) { URI.parse('https://clochers.org/Fichiers_HTML/Accueil/Accueil_clochers/71/accueil_71294c.htm') }
      it 'returns a single name' do
        body = File.read(File.join(__dir__, 'single_result.htm'))
        expect(extract_churches(fake_uri, body).map(&:name)).to eq ['Église Saint-Denis']
      end
    end

    context 'when there are multiple related cities' do
      let(:fake_uri) { URI.parse('https://clochers.org/Fichiers_HTML/Accueil/Accueil_clochers/71/accueil_71294.htm') }
      pending 'works' do
        body = File.read(File.join(__dir__, 'multi_communes.htm'))
        expect(extract_churches(fake_uri, body).map(&:name)).to eq ['...']
      end
    end

    context 'when there are multiple buildings in the city' do
      let(:fake_uri) { URI.parse('https://clochers.org/Fichiers_HTML/Accueil/Accueil_clochers/71/accueil_71294.htm') }
      it 'works ' do
        body = File.read(File.join(__dir__, 'multi_buildings.htm'))
        expect(extract_churches(fake_uri, body).map(&:name)).to eq [
          "Église de l'Assomption-de-la-Bienheureuse-Vierge-Marie dite aussi Notre-Dame des Hautes-Forêts",
          'Chapelle Saint-Jacques'
        ]
      end
    end

    context 'when there are many buildings in the city' do
      let(:fake_uri) { URI.parse('https://clochers.org/Fichiers_HTML/Accueil/Accueil_clochers/71/accueil_71294.htm') }
      it 'works ' do
        body = File.read(File.join(__dir__, 'many_buildings.htm'))
        expect(extract_churches(fake_uri, body).map(&:name)).to eq [
          'Chapelle du Sacré-Cœur-de-Jésus',
          'Chapelle Sainte-Odile',
          'Chapelle Saint Pierre',
          "Église de l'Assomption",
          'Église Saint-Symphorien'
        ]
      end
    end
  end
end
