#
# Original author: the1drewharris
#
# Things that still should be done:
# - apply SUSE Cloud admin CSS to views
# - encrypt the password in xml document

require "net/http"
require "uri"
require "rexml/document"
require "cgi"

class XMLAPIRequestError < StandardError
  def initialize(exception); @exception = exception end
  def message;               @exception.message     end
  alias_method :to_s, :message
end

class XMLAPIResponseFailure < StandardError
  attr_reader :response

  def initialize(xml_response)
    @response = xml_response
  end

  def message
    "%d %s" % [ @response.code, @response.message ]
  end

  alias_method :to_s, :message
end

class UcsController < ApplicationController
  CREDENTIALS_XML_PATH = '/etc/crowbar/cisco-ucs/credentials.xml'
  COMPUTE_SERVICE_PROFILE = 'suse-cloud-compute'
  STORAGE_SERVICE_PROFILE = 'suse-cloud-storage'

  DEFAULT_EDIT_CLASS_ID = "computePhysical"

  before_filter :authenticate, :only => [ :edit, :update ]
  #before_filter :authenticate, :except => [ :settings, :login ]

  def handle_exception(exception, log_message, ui_message)
    logger.warn "Cisco UCS: #{log_message}: #{exception}"
    redirect_to :back, :notice => (ui_message % truncate(exception.to_s))
  end

  rescue_from SocketError, XMLAPIRequestError do |e|
    handle_exception(e, e, "Failed to connect to UCS API server (%s)")
  end

  rescue_from XMLAPIResponseFailure do |e|
    handle_exception(e, "HTTP request to XML API failed",
                     "Error receiving response from UCS API server (%s)")
  end

  rescue_from REXML::ParseException do |e|
    handle_exception("failed to parse response from XML API",
                     "Received invalid response from UCS API server (%s)")
  end

  # Render the login page, where the URL, username, and password can
  # be changed.
  def settings
    if have_credentials?
      read_credentials
    else
      @ucs_url  = @username = @password = ""
    end
  end

  # Store the provided credentials, then attempt to log in and get our
  # session cookie.  The id we are passing to the #show action can be
  # changed as indicated in the notes for #edit.
  def login
    # Persist the credentials even before we know they're right, because
    # if the user got them wrong, it's nicer to make them edit the incorrect
    # settings than have to type them all out from scratch.
    write_credentials(params[:ucs_url], params[:username], params[:password])
    read_credentials

    logger.debug "Cisco UCS: about to aaaLogin"
    cookie = aaaLogin(@ucs_url, @username, @password)
    logger.debug "Cisco UCS: cookie returned from aaaLogin: " + cookie.inspect
    # ucs_login will issue a redirect if authentication failed.
    return unless cookie

    # Login succeeded
    set_ucs_session_cookie(cookie)
    redirect_to :action => :edit
  end

  def logout
    unless logged_in?
      redirect_to ucs_settings_path, :notice => 'Already logged out from UCS.'
      return
    end

    read_credentials # need API endpoint
    logoutDoc = sendXML("<aaaLogout inCookie='#{ucs_session_cookie}'/>")
    logger.debug "UCS logout: " + logoutDoc.root.inspect
    set_ucs_session_cookie(nil)
    redirect_to ucs_settings_path, :notice => 'Logged out from UCS.'
  end

  # params[:id] can be:
  #   - computeBlade to only show blade servers
  #   - lsServer for policies
  #   - computeRackUnit for servers not in a equipmentChassis
  #   - computePhysical for a list of all physical servers
  def edit
    # N.B. the ls:Server class encapsulates:
    #
    #   - service profiles
    #   - service profile initial templates
    #   - service profile initial templates
    #
    # rather than what one might intuitively expect, which is for
    # service profile templates to have a separate class to service
    # profile instances.  This can be seen by visiting the Cisco UCS
    # web UI, clicking on the API Model Documentation, selecting
    # "Classes" then "ls:Server", and scrolling down to the "type"
    # attribute which references the "ls:Type" class, e.g.:
    #   http://192.168.124.26/docs/MO-lsServer.html#type
    @serverPolicies = configResolveClass("lsServer")

    @serverPolicies.elements.each('configResolveClass/outConfigs/#{myClass}') do |element|
      # filter out service profile instances, as per above
      next unless element.attributes["type"] =~ /template/

      # check policies for matches to "hardcoded" named values
      case element.attributes["name"]
      when STORAGE_SERVICE_PROFILE
        @storage = true
      when COMPUTE_SERVICE_PROFILE
        @compute = true
      end
    end
    @ucsDoc = configResolveClass(params[:id] || DEFAULT_EDIT_CLASS_ID)
    @rackUnits = configResolveClass("computeRackUnit")
    @chassisUnits = configResolveClass("equipmentChassis")
  end

  # This will perform the update action and should redirect to edit once complete.
  def update
    ucsDoc = configResolveClass(params[:id])
    case params[:updateAction]
    when "compute"
      action_xml = COMPUTE_SERVICE_PROFILE
    when "storage"
      action_xml = STORAGE_SERVICE_PROFILE
    when "up"
      action_xml = "admin-up"
    when "down"
      action_xml = "admin-down"
    when "reboot"
      action_xml = "cycle-immediate"
    else
      # nothing to do but send back to edit
      redirect_to ucs_edit_path
      return
    end

    @updateDoc = "<configConfMos inHierarchical='false' cookie='#{ucs_session_cookie}'><inConfigs>"
    @action_xml = action_xml
    # add xml elements for each selected server
    if action_xml == COMPUTE_SERVICE_PROFILE || action_xml == STORAGE_SERVICE_PROFILE
      instantiate_service_profile(ucsDoc, action_xml)
    else
      # should run for up, down, reboot
      send_power_commands(ucsDoc, action_xml)
    end
    @updateDoc = @updateDoc + "</inConfigs></configConfMos>"
    @serverResponseDoc = sendXML(@updateDoc)
    redirect_to ucs_edit_path, :notice => 'Your update has been applied.'
  end

  private

  def instantiate_service_profile(ucsDoc, action_xml)
    ucsDoc.elements.each('configResolveClass/outConfigs/#{myClass}') do |element|
      if params[element.attributes["dn"]] == "1"
        @instantiateNTemplate = sendXML(<<-EOXML)
          <lsInstantiateNTemplate
              cookie='#{ucs_session_cookie}'
              dn='org-root/ls-#{action_xml}'
              inTargetOrg='org-root'
              inServerNamePrefixOrEmpty='sc'
              inNumberOf='1'
              inHierarchical='false'>
          </lsInstantiateNTemplate>
        EOXML
        @instantiateNTemplate.elements.each('lsInstantiateNTemplate/outConfigs/lsServer') do |currentPolicy|
          @currentPolicyName = currentPolicy.attributes['dn']
          @currentPolicyXML = currentPolicy
        end
        @updateDoc = @updateDoc + <<-EOXML
          <pair key='#{@currentPolicyName}/pn'>
            <lsBinding pnDn='#{element.attributes["dn"]}'>
            </lsBinding>
          </pair>"
        EOXML
      end
    end
  end

  def send_power_commands(ucsDoc, action_xml)
    ucsDoc.elements.each('configResolveClass/outConfigs/#{myClass}') do |element|
      #check_box_tag(element.attributes["dn"])
      if params[element.attributes["dn"]] == "1"
        @updateDoc = @updateDoc + <<-EOXML
          <pair key='#{element.attributes["dn"]}'>
            <#{element.name} adminPower='#{action_xml}' dn='#{element.attributes["dn"]}'>
            </#{element.name}>
          </pair>
        EOXML
      end
    end
  end

  def ucs_session_cookie
    session[:ucs_cookie]
  end

  def set_ucs_session_cookie(cookie)
    session[:ucs_cookie] = cookie
    logger.debug "Cisco UCS: set session cookie to #{cookie}"
  end

  helper_method :logged_in?, :readonly

  def logged_in?
    !! ucs_session_cookie
  end

  # Login fields should be read-only if logged in
  def readonly
    logged_in? ? 'readonly' : ''
  end

  # Use this to protect error messages which are intended to go in the
  # flash from causing a ActionDispatch::Cookies::CookieOverflow error
  # (the session cookie has a limit of 4k) or making the web UI look
  # ugly.
  def truncate(message)
    return message if message.size < 80
    message.slice(0, 80) + '...'
  end

  def sendXML(xmlString = "")
    uri = URI.parse(@ucs_url)
    http = Net::HTTP.new(uri.host, uri.port)
    api_request = Net::HTTP::Post.new(uri.request_uri)
    api_request.body = xmlString

    begin
      api_response = http.request(api_request)
    rescue StandardError => e
      raise XMLAPIRequestError, e
    end

    unless api_response.is_a? Net::HTTPSuccess
      raise XMLAPIResponseFailure, api_response
    end

    return REXML::Document.new(api_response.body)
  end

  def aaaLogin(ucs_url, username, password)
    if ucs_url.blank?
      logger.debug "Cisco UCS: missing login URL"
      redirect_to ucs_settings_path, :notice => "You must provide a login URL."
      return nil
    elsif ! ucs_url.end_with? '/nuova'
      logger.debug "Cisco UCS: login URL didn't have the correct '/nuova' ending"
      redirect_to ucs_settings_path, :notice => "Login URL should end in '/nuova'."
      return nil
    elsif username.blank?
      logger.debug "Cisco UCS: missing login name"
      redirect_to ucs_settings_path, :notice => "You must provide a login name."
      return nil
    elsif password.blank?
      logger.debug "Cisco UCS: missing login password"
      redirect_to ucs_settings_path, :notice => "You must provide a login password."
      return nil
    end

    logger.debug "Cisco UCS: credentials all present"

    begin
      loginDoc = sendXML("<aaaLogin inName='#{username}' inPassword='#{password}'></aaaLogin>")
    rescue REXML::ParseException => e
      logger.warn "Cisco UCS: REXML parse failure during aaaLogin: #{e}"
      message = "Failed to parse response from UCS API server; did your API URL end in '/nuova'?"
      redirect_to ucs_settings_path, :notice => message
      return nil
    end

    ucs_cookie = cookie_from_response(loginDoc)
    unless ucs_cookie
      # FIXME: improve cookie validation
      redirect_to ucs_settings_path, :notice => "Login failed to obtain session cookie from Cisco UCS"
      return nil
    end

    return ucs_cookie
  end

  def cookie_from_response(response)
    response ? response.root.attributes['outCookie'] : nil
  end

  def configResolveClass(classID)
    ucsDoc = sendXML("<configResolveClass cookie='#{ucs_session_cookie}' classId='#{classID}'></configResolveClass>")
    return ucsDoc
  end

  def authenticate
    unless have_credentials?
      redirect_to ucs_settings_path, :notice => t('barclamp.cisco_ucs.login.provide_creds')
      return
    end

    unless logged_in?
      redirect_to ucs_settings_path, :notice => t('barclamp.cisco_ucs.login.please_login')
      return
    end

    read_credentials
  end

  def have_credentials?
    File.exist?(CREDENTIALS_XML_PATH)
  end

  def read_credentials
    File.open(CREDENTIALS_XML_PATH) do |file|
      cloudDoc = REXML::Document.new(file)
      cloudDoc.elements.each('ucs/cloud') do |element|
        @ucs_url  = element.attributes["url"]
        @username = element.attributes["username"]
        @password = element.attributes["password"]
      end
    end
  end

  def write_credentials(ucs_url, username, password)
    File.open( CREDENTIALS_XML_PATH, "w" ) do |file|
      file.puts "<ucs><cloud url='#{ucs_url}' username='#{username}' password='#{password}' /></ucs>"
    end
  end
end
