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

class CiscoUcsController < ApplicationController
  $cloudXMLpath = "cloud.xml"
  #show the login form
  def index
    @myCloudXML = check4CloudXML()
    if @myCloudXML == false
      session[:needCloudXML] = true
    else
      if params[:updateLogin] == "1"
        session[:needCloudXML] = true
        thisCloud = readCloudXML()
        @asIsURL = thisCloud[:myURL]
        @asIsName = thisCloud[:myName]
        @asIsPass = thisCloud[:myPassword]
      else
        thisCloud = readCloudXML()
        session[:needCloudXML] = false
        login(thisCloud[:myURL], thisCloud[:myName], thisCloud[:myPassword])
      end
    #end if myCloudXML evaluation
    end  
  end
  
  #do the action of logging in and getting our cookie
  #the id we are passing to show can be changed as indicated in the notes for edit
  def login(thisURL=params[:thisURL], myName=params[:myName], myPassword=params[:myPassword])
    session[:myURL] = thisURL
    session[:myCookie] = aaaLogin(thisURL, myName, myPassword)
    if session[:needCloudXML] == true
      createCloudXML(thisURL, myName, myPassword)
    end
    redirect_to :action => :edit, :id => "computePhysical"
  end
  
  #the classID can be changed here to be computeBlade to only show blade servers, or lsServer for policies, or  computeBlade or computeRackUnit for servers not in a equipmentChassis, or computePhysical for a list of all phyical servers
  def edit(thisURL=session[:myURL], myCookie=session[:myCookie], classID=params[:id])
    @serverPolicies = configResolveClass(thisURL, myCookie, "lsServer")
    @serverPolicies.elements.each('configResolveClass/outConfigs/#{myClass}') do |element|
      #check policies for matches to "hardcoded" named values
      case element.attributes["name"]
      when "susecloudstorage"  
        @storage = true
      when "susecloudcompute"
        @compute = true
      end 
    end
    @ucsDoc = configResolveClass(thisURL, myCookie, classID)
    @rackUnits = configResolveClass(thisURL, myCookie, "computeRackUnit")
    @chassisUnits = configResolveClass(thisURL, myCookie, "equipmentChassis")
    @logoutDoc = aaaLogout(session[:myURL], session[:myCookie])
    session[:active] = false
  end
  
  #this will perform the update action and SHOULD redirect to edit once complete
  def update(thisURL=session[:myURL], myCookie=session[:myCookie], classID=params[:id])
    if session[:active] == false
      session[:myCookie] = aaaLogin(thisURL, session[:myName], session[:myPassword])
    end
    ucsDoc = configResolveClass(thisURL, myCookie, classID)
    case params[:updateAction] 
    when "compute" 
      action_xml = "susecloudcompute"
    when "storage"
      action_xml = "susecloudstorage"
    when "up"
      action_xml = "admin-up"
    when "down" 
      action_xml = "admin-down"
    when "reboot"
      action_xml = "cycle-immediate"
    else
      #nothing to do but send back to edit
      render edit
    end
    @updateDoc = "<configConfMos inHierarchical='false' cookie='#{myCookie}'><inConfigs>"
    @action_xml = action_xml
    #add xml elements for each selected server
    if action_xml == "susecloudcompute" || action_xml == "susecloudstorage"
      ucsDoc.elements.each('configResolveClass/outConfigs/#{myClass}') do |element|
        if params[element.attributes["dn"]] == "1"
          @instantiateNTemplate = sendXML(session[:myURL], "<lsInstantiateNTemplate cookie='#{myCookie}' dn='org-root/ls-#{action_xml}' inTargetOrg='org-root' inServerNamePrefixOrEmpty='sc' inNumberOf='1' inHierarchical='false'> </lsInstantiateNTemplate>")
          @instantiateNTemplate.elements.each('lsInstantiateNTemplate/outConfigs/lsServer') do |currentPolicy|
            @currentPolicyName = currentPolicy.attributes['dn']
            @currentPolicyXML = currentPolicy
          end
          @updateDoc = @updateDoc + "<pair key='#{@currentPolicyName}/pn'><lsBinding pnDn='#{element.attributes["dn"]}'></lsBinding></pair>"
        end
      end
    #else should run for up, down, reboot
    else
      ucsDoc.elements.each('configResolveClass/outConfigs/#{myClass}') do |element|
        #check_box_tag(element.attributes["dn"])
        if params[element.attributes["dn"]] == "1"
          @updateDoc = @updateDoc + "<pair key='#{element.attributes["dn"]}'><#{element.name} adminPower='#{action_xml}' dn='#{element.attributes["dn"]}'></#{element.name}></pair>"
        end
      #end loop over xml elements
      end
    #end up, down, reboot
    end
    @updateDoc = @updateDoc + "</inConfigs></configConfMos>"
    @serverResponseDoc = sendXML(thisURL, @updateDoc)
    #notice = 'Your update has been applied.'
    redirect_to :action => :edit, :id => "computePhysical"
  end

  private
  def sendXML(thisURL=session[:myURL], xmlString="")
     uri = URI.parse(thisURL)
     #this code worked fine with the simulator, but caused issues in production
	 #this if for checking that the URL gives us a response before we send
     #begin
     # checkResponse = Net::HTTP.get_response(uri)
     # checkResponse.code == "200"
     #rescue 
     #end
     http = Net::HTTP.new(uri.host, uri.port)
     request = Net::HTTP::Post.new(uri.request_uri)
     request.body = xmlString
     xmlRequest = http.request(request)
     requestDoc = REXML::Document.new(xmlRequest.body)
     return requestDoc
   end
   
   def aaaLogin(thisURL, myName, myPassword)
     loginDoc = sendXML(thisURL, "<aaaLogin inName='#{myName}' inPassword='#{myPassword}'></aaaLogin>")
     # set a variable for the value of the Cookie we got back from the web service (outCookie) 
     myCookie = loginDoc.root.attributes['outCookie']
     #Insert error handling in case a cookie is not defined here
     session[:myCookie] = myCookie
     session[:myName] = myName
     session[:myPassword] = myPassword
     session[:active] = true
     return myCookie
   end
   
   def aaaLogout(thisURL=session[:myURL], myCookie=session[:myCookie])
	#We disabled the logout code due to problems experienced in the real world environment.
   #logoutDoc = sendXML(thisURL, "<aaaLogout inCookie='#{myCookie}'/>")
	logoutDoc = 'true'
     #session[:active] = false
     return logoutDoc
   end
   
   def configResolveClass(thisURL, myCookie, classID)
     ucsDoc = sendXML(thisURL, "<configResolveClass cookie='#{myCookie}' classId='#{classID}'></configResolveClass>")
     return ucsDoc
   end
   
   def check4CloudXML(fileName=$cloudXMLpath)
     myCloudXML=File.exist?(fileName)
     return myCloudXML
   end
   
   def readCloudXML(fileName=$cloudXMLpath)
     cloudFile = File.new(fileName)
     thisCloud = Hash.new()
     cloudDoc = REXML::Document.new cloudFile
     cloudDoc.elements.each('ucs/cloud') do |element|
       thisCloud[:myURL] = element.attributes["url"]
       thisCloud[:myName] = element.attributes["name"]
       thisCloud[:myPassword] = element.attributes["mypass"]
     end
     return thisCloud
   end
   
   def createCloudXML(thisURL, myName, myPassword)
    @myCloudXML = check4CloudXML()
    if @myCloudXML == true
      File.delete( $cloudXMLpath )
    end
     File.open( $cloudXMLpath, "w" ) do |the_file|
      the_file.puts "<ucs><cloud url='#{thisURL}' name='#{myName}' mypass='#{myPassword}' /></ucs>"
     end
   end
   
end
