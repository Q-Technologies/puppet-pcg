require 'spec_helper'
describe 'osbaseline' do
  context 'with default values for all parameters' do
    it { should contain_class('osbaseline') }
  end
end
