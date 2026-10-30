class Api::FaqsController < ApplicationController
  def index
    render json: Faq.sections
  end
end
