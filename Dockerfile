FROM nginx:alpine

WORKDIR /app

COPY . /user/share/nginx/html

RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "start"]


