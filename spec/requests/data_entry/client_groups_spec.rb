require File.join(File.dirname(__FILE__), '..', '..', 'spec_helper.rb')

given "a client_group exist" do
  ClientGroup.all.destroy!
end

given "an admin user exist" do
  User.all.destroy!
  load_fixtures :users
  response = request url(:perform_login), :method => "PUT", :params => {:login => 'admin', :password => 'password'}
  response.should redirect
end

describe "/data_entry/client_groups", :given => "an admin user exist" do
  describe "GET" do
    before(:each) do
      @response = request("/data_entry/client_groups/new")
    end

    it "responds successfully" do
      @response.should be_successful
    end
  end
end

describe "/data_entry/client_groups/edit", :given => "an admin user exist" do
  describe "PUT" do
    before(:each) do
      @response = request("/data_entry/client_groups/edit")
    end

    it "responds successsfully" do
      @response.should be_successful
    end
  end
end



