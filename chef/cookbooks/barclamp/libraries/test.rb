
if $0 == __FILE__

  require "minitest/autorun"
  require "conduit_resolver"
  require "barclamp_library"

  class TestIFRemap < MiniTest::Test
    def build_node_object(speeds)
      node = {
        "crowbar_ohai" => {
          "detected" => {
            "network" => {
            }
          }
        }
      }
      speeds.each {|x|
        node["crowbar_ohai"]["detected"]["network"][x] = {
          "speeds" => [x]
        }
      }
      mock = MiniTest::Mock.new
      # 99 is probably too much here. But node.automatic_attrs is called
      # a lot in the conduit resolver. So we're on the save side here.
      99.times { |_unused_| mock.expect(:automatic_attrs, node, []) }
      mock
    end

    def test_match_100m
      node = build_node_object ["100m", "1g"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal "100m", b.resolve_if_ref("100m1")
    end

    def test_match_1g
      node = build_node_object ["100m", "1g"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal "1g", b.resolve_if_ref("1g1")
    end

    def test_10m_upgrade
      node = build_node_object ["100m", "1g"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal "100m", b.resolve_if_ref("+10m1")
    end

    def test_10gdowngrade
      node = build_node_object ["10m", "100m", "1g"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal "1g", b.resolve_if_ref("-10g1")
    end

    def test_1gdowngrade
      node = build_node_object ["10m", "100m"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal "100m", b.resolve_if_ref("-1g1")
    end

    def test_1g_any
      node = build_node_object ["10m", "100m"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal "100m", b.resolve_if_ref("?1g1")
    end

    def test_1g_any_up
      node = build_node_object ["10m", "100m", "10g"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal "10g", b.resolve_if_ref("?1g1")
    end

    def test_non_listed_items_with_one_valid
      node = build_node_object ["10m", "100m", "10g", "0g", "5k", "fred"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal "10g", b.resolve_if_ref("?1g1")
    end

    def test_non_listed_items_with_no_valid
      node = build_node_object ["0g", "5k", "fred"]
      b = BarclampLibrary::Barclamp::NodeConduitResolver.new(node)
      assert_equal nil, b.resolve_if_ref("?1g1")
    end
  end
end
