defmodule ClienteTest do
  use ExUnit.Case
  doctest Cliente

  test "greets the world" do
    assert Cliente.hello() == :world
  end
end
