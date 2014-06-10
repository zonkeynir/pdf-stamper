# = pdf/stamper.rb -- PDF template stamping.
#
#  Copyright (c) 2007-2012 Jason Yates

require 'rbconfig'
require 'fileutils'
#require 'tmpdir'
#require 'active_support/inflector/methods'

include FileUtils

if RUBY_PLATFORM =~ /java/ # ifdef to check if your using JRuby
  require 'pdf/stamper/jruby'
else
  require 'pdf/stamper/rjb'
end

module PDF
  class Stamper
    VERSION = "0.6.0"
    
    
    # PDF::Stamper provides an interface into iText's PdfStamper allowing for the
    # editing of existing PDFs as templates. PDF::Stamper is not a PDF generator,
    # it allows you to edit existing PDFs and use them as templates.
    #
    # == Creation of templates
    #
    # Templates currently can be created using Adobe LiveCycle Designer
    # or Adobe Acrobat Professional. Using Acrobat Professional, you can create
    # a form and add textfields, checkboxes, radio buttons and buttons for images.
    #
    # == Example
    #
    # pdf = PDF::Stamper.new("my_template.pdf")
    # pdf.text :first_name, "Jason"
    # pdf.text :last_name, "Yates"
    # pdf.image :photo, "photo.jpg"
    # pdf.checkbox :hungry
    # pdf.save_as "my_output"

    def initialize(pdf = nil)
      template(pdf) if ! pdf.nil?
    end
  
    def template(template)
      reader = PdfReader.new(template)
      @baos = ByteArrayOutputStream.new
      @stamp = PdfStamper.new(reader, @baos)
      @form = @stamp.getAcroFields()
      @canvas = @stamp.getOverContent(1)
    end
  
    # Set a button field defined by key and replaces with an image.
    def image(key, image_path)
      # Idea from here http://itext.ugent.be/library/question.php?id=31 
      # Thanks Bruno for letting me know about it.
      img = Image.getInstance(image_path)
      img_field = @form.getFieldPositions(key.to_s)

      rect = Rectangle.new(img_field[1], img_field[2], img_field[3], img_field[4])
      img.scaleToFit(rect.width, rect.height)
      img.setAbsolutePosition(
        img_field[1] + (rect.width - img.scaledWidth) / 2,
        img_field[2] + (rect.height - img.scaledHeight) /2
      )

      cb = @stamp.getOverContent(img_field[0].to_i)
      cb.addImage(img)
    end
    def fields
     @form.getFields
    end
    # PDF::Stamper allows setting metadata on the created PDF by passing
    # the parameters to the set_more_info function. Our implementation here
    # is slightly different from iText, in that we only receive a single key/value
    # pair at a time, instead of a Map<string,string> since that is slightly
    # more complex to bridge properly from ruby to java.
    # 
    # Possible keys include "Creator". All values here are strings.
    # 
    def set_metadata(key, value)
      params = java.util.HashMap.new()
      params.put(key.to_s, value)
      @stamp.setMoreInfo(params)
    end
    
    # If you want to have iText reset some of the metadata, this function will
    # cause iText to use its default xml metadata.
    def reset_xmp_metadata()
      @stamp.setXmpMetadata("".to_java_bytes)
    end
    
    # Set a textfield defined by key and text to value
    def text(key, value)
      @form.setField(key.to_s, value.to_s) # Value must be a string or itext will error.
    end

    
    # Takes the PDF output and sends as a string.
    #
    # Here is how to use it in rails:
    #
    # def send 
    #     pdf = PDF::Stamper.new("sample.pdf") 
    #     pdf.text :first_name, "Jason"
    #     pdf.text :last_name, "Yates" 
    #     send_data(pdf.to_s, :filename => "output.pdf", :type => "application/pdf",:disposition => "inline")
    # end   
    def to_s
      fill
      String.from_java_bytes(@baos.toByteArray)
    end


    # Set a checkbox to checked
    def checkbox(key)
      field_type = @form.getFieldType(key.to_s)
      return unless is_checkbox(field_type)

      all_states = @form.getAppearanceStates(key.to_s)
      yes_state = all_states.reject{|x| x == "Off"}
      
      
      @form.setField(key.to_s, yes_state.first) unless (yes_state.size == 0)
    end
    
    # Get checkbox values
    def get_checkbox_values(key)
      field_type = @form.getFieldType(key.to_s)
      return unless is_checkbox(field_type)

      @form.getAppearanceStates(key.to_s)
    end

    def circle(x, y, r)
      @canvas.circle(x, y, r)
    end

    def ellipse(x, y, width, height)
      @canvas.ellipse(x, y, x + width, y + height)
    end

    def rectangle(x, y,  width, height)
      @canvas.rectangle(x, y, width, height)
    end

    # Example
    # barcode("PDF417", "2d_barcode", "Barcode data...", AspectRatio: 0.5)
    def barcode(format, key, value, opts = {})
      bar = create_barcode(format)
      bar.setText(value)
      opts.each do |name, opt|
        #bar.send("set#{name.to_s.camelize}", opt) #Camelize is not present outside of Rails by default
        bar.send("set#{name.to_s}", opt)
      end

      coords = @form.getFieldPositions(key.to_s)
      rect = create_rectangle(coords)

      barcode_img = bar.getImage
      barcode_img.scalePercent(100, 100 * bar.getYHeight)
      barcode_img.setAbsolutePosition(
          coords[1] + (rect.getWidth - barcode_img.getScaledWidth) / 2,
          coords[2] + (rect.getHeight - barcode_img.getScaledHeight) / 2
      )

      cb = @stamp.getOverContent(coords[0].to_i)
      cb.addImage(barcode_img)
    end

    # this has to be called *before* setting field values
    def set_font(font_name)
      itr = @form.getFields.keySet.iterator
      while itr.hasNext
        field = itr.next
        @form.setFieldProperty(field, 'textfont', create_font(font_name), nil)
      end
    end
    
    # Saves the PDF into a file defined by path given. If you want to save
    # to a string/buffer, just use .to_s directly.
    def save_as(file)
      File.open(file, "wb") { |f| f.write to_s }
    end
    
    private

    def fill
      @canvas.stroke()
      @stamp.setFormFlattening(true)
      @stamp.close
    end
  end
end
