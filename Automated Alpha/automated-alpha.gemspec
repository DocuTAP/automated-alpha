# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = 'automated-alpha'
  spec.version       = '1.0'
  spec.author        = 'DocuTAP Release Team'
  spec.email         = 'release-admin@docutap.com'
  spec.summary       = "Major Release Alpha Preparation Automation"
  spec.description   = "Prepares Alpha sites for the start of a new major release cycle"
  spec.homepage      = "https://github.com/DocuTAP/automated-alpha"
  spec.license       = "MIT"
  spec.files         = Dir['lib/restore_from_backup.rb'] + Dir['config/SAMPLE_DT043_conifg.yml']
end