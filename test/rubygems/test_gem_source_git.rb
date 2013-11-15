require 'rubygems/test_case'
require 'rubygems/source'

class TestGemSourceGit < Gem::TestCase

  def setup
    super

    @name, @version, @repository, @head = git_gem

    @hash = Digest::SHA1.hexdigest @repository

    @source = Gem::Source::Git.new @name, @repository, 'master', false
  end

  def test_checkout
    @source.checkout

    assert_path_exists File.join @source.install_dir, 'a.gemspec'
  end

  def test_checkout_submodules
    source = Gem::Source::Git.new @name, @repository, 'master', true

    git_gem 'b'

    Dir.chdir 'git/a' do
      system @git, 'submodule', '--quiet', 'add', File.expand_path('../b'), 'b'
      system @git, 'commit', '--quiet', '-m', 'add submodule b'
    end

    source.checkout

    assert_path_exists File.join source.install_dir, 'a.gemspec'
    assert_path_exists File.join source.install_dir, 'b/b.gemspec'
  end

  def test_cache
    @source.cache

    assert_path_exists @source.repo_cache_dir

    Dir.chdir @source.repo_cache_dir do
      assert_equal @head, Gem::Util.popen(@git, 'rev-parse', 'master').strip
    end
  end

  def test_cache
    @source.cache

    assert @source.cache
  end

  def test_dir_shortref
    @source.cache

    assert_equal @head[0..11], @source.dir_shortref
  end

  def test_equals2
    assert_equal @source, @source

    assert_equal @source, @source.dup

    source =
      Gem::Source::Git.new @source.name, @source.repository, 'other', false

    refute_equal @source, source

    source =
      Gem::Source::Git.new @source.name, 'repo/other', @source.reference, false

    refute_equal @source, source

    source =
      Gem::Source::Git.new 'b', @source.repository, @source.reference, false

    refute_equal @source, source

    source =
      Gem::Source::Git.new @source.name, @source.repository, @source.reference,
                           true

    refute_equal @source, source
  end

  def test_load_spec
    spec = @source.load_spec @name

    assert_equal "#{@name}-#{@version}", spec.full_name
  end

  def test_install_dir
    @source.cache

    expected = File.join Gem.dir, 'bundler', 'gems', "a-#{@head[0..11]}"

    assert_equal expected, @source.install_dir
  end

  def test_repo_cache_dir
    expected =
      File.join Gem.dir, 'cache', 'bundler', 'git', "a-#{@hash}"

    assert_equal expected, @source.repo_cache_dir
  end

  def test_rev_parse
    @source.cache

    assert_equal @head, @source.rev_parse

    Dir.chdir @repository do
      system @git, 'checkout', '--quiet', '-b', 'other'
    end

    master_head = @head

    git_gem 'a', 2

    source = Gem::Source::Git.new @name, @repository, 'other', false

    source.cache

    refute_equal master_head, source.rev_parse
  end

  def test_uri_hash
    assert_equal @hash, @source.uri_hash

    source =
      Gem::Source::Git.new 'a', 'http://git@example/repo.git', 'master', false

    assert_equal '291c4caac7feba8bb64c297987028acb3dde6cfe',
                 source.uri_hash

    source =
      Gem::Source::Git.new 'a', 'HTTP://git@EXAMPLE/repo.git', 'master', false

    assert_equal '291c4caac7feba8bb64c297987028acb3dde6cfe',
                 source.uri_hash
  end

end

