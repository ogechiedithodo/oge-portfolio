FROM nginx:alpine

WORKDIR /app

COPY . /usr/share/nginx/html

COPY . .

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]


