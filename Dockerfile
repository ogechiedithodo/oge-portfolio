FROM nginx:alpine

WORKDIR /app

COPY . /user/share/nginx/html

COPY . .

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]


