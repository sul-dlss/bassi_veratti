class AboutController < ApplicationController
  # To create a new about page, create a partial with the URL name you want containing the actul page content
  # If your action has logic that needs to be run before the view, create a method, call "show" at the end of it, create a view partical o match,
  # and add a custom route in the routes.rb file
  def contact
    @from = params[:from]
    @subject = params[:subject]
    @name = params[:name]
    @email = params[:email]
    @message = params[:message]

    if request.post?
      if @message.blank?
        flash.now[:error] = t("bassi.about.contact_error")
      else
        BassiVerattiMailer.contact_message(:params => params, :request => request).deliver
        flash[:notice] = t("bassi.about.contact_message_sent")
        @message = nil
        @name = nil
        @email = nil
        unless @from.blank?
          redirect_to(@from)
          return
        end
      end
    end
    show
  end

  def show
    @page_name = params[:id] || action_name # see if the page to show is specified in the ID parameter (coming via a route) or custom method (via the action name)
    @page_name = 'project' unless lookup_context.exists?(@page_name, 'about', true) # default to project page if requested partial doesn't exist
    @page_title = t("bassi.about.#{@page_name}_title") # set the page title
    @params = params
    @no_nav = (@page_name == 'terms_dialog' ? true : false)
    render :show
  end

  def background
    @page_title = t("bassi.background.title") # set the page title
  end
end
